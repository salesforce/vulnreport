##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

require 'rubygems'
require 'sinatra/base'
require 'tilt/erb'
require 'rack/ssl'
require 'rack/csrf'
require 'base64'
require 'savon'
require 'nokogiri'
require 'resolv'
require 'ruby-saml'
require 'json'
require 'zip'
require 'chronic'
require 'net/http'
require 'uri'
require 'ipaddr'
require 'cgi'
require 'redis'
require 'active_support/core_ext/date_time/calculations'
require 'active_support/time'
require 'rufus/scheduler'
require 'date'
require 'securerandom'
require 'pony'
require 'rollbar'
require 'pdfkit'

#Load in environment vars from DotEnv
require 'dotenv'
Dotenv.load

require './lib/funcs'
require './models/init'
require './lib/auth'
require './lib/VRCron'
require './lib/VRDashConfig'
require './lib/VRLinkedObject'

if(onHeroku?)
	#Only load this gem if running on Heroku. If not on Heroku
	#this dep should be handled by local library install, not gem
	require 'wkhtmltopdf-heroku'
end

# Load all cron files and VRDashConfigs and register them later
Dir["./crons/*.rb"].each {|cronfile| require cronfile}
Dir["./customDashes/*.rb"].each {|dcfile| require dcfile}
Dir["./linkedObjects/*.rb"].each {|lofile| require lofile}

##
# Main Vulnreport class
#
# @author Tim Bach <tim.bach@salesforce.com>, Salesforce
class Vulnreport < Sinatra::Base
	use Rack::SSL
	use Rack::Session::Cookie, :key => 'vr.session',
	                           :path => '/',
	                           :expire_after => 60*60*3, # In seconds
	                           :secret => ((ENV['VR_SESSION_SECRET'].nil?) ? 'vrsession' : ENV['VR_SESSION_SECRET'])

	use Rack::Csrf, :raise => true, :skip => ['POST:/saml/.*', 'POST:/search', 'POST:/markNotifsSeen']

	#Set up Sinatra
	set :root, File.dirname(__FILE__)
	set :logging, true
	set :method_override, true
	set :inline_templates, true
	set :static, true

	whitelist = []
	ssoUrl = getSetting('AUTH_SSO_TARGET_URL').to_s
	vrRoot = getSetting('VR_ROOT').to_s
	whitelist << vrRoot if(!vrRoot.nil? && !vrRoot.strip.empty?)
	whitelist << "https://" + URI.parse(ssoUrl).host if(!ssoUrl.nil? && !ssoUrl.strip.empty?)
	whitelist << "https://localhost"
	
	set :protection, :origin_whitelist => whitelist, :except => [:frame_options, :remote_token]

	configure do
		Rollbar.configure do |config|
		    config.access_token = ENV['ROLLBAR_ACCESS_TOKEN'] #server access token
		    config.environment = Sinatra::Base.environment
		    config.framework = "Sinatra: #{Sinatra::VERSION}"
		    config.root = Dir.pwd
		end

		vr_mail_method = getSetting('VR_MAIL_METHOD')
		if(!vr_mail_method.nil? && vr_mail_method == 'custom')
			logputs "Setting mail method to custom"
			Pony.options = {
				:via => :smtp,
				:via_options => {
					:address => getSetting('VR_MAIL_ADDR'),
					:port => getSetting('VR_MAIL_PORT').to_i,
					:domain => getSetting('VR_MAIL_DOMAIN'),
					:user_name => getSetting('VR_MAIL_USER'),
					:password => getSetting('VR_MAIL_PASS'),
					:authentication => :plain,
					:enable_starttls_auto => true
				}
			}
		end

		set :redis, Redis.new(:url => ENV['REDIS_URL'])
		set :vrurl, getSetting('VR_ROOT').to_s
		set :vrname, getSetting('VR_INS_NAME').to_s
		set :vrfooter, getSetting('VR_FOOTER').to_s

		#Register custom dashconfigs
		vrdcs = Array.new
		VRDashConfig.each do |dc|
			registerVRDashConfig(dc)
			vrdcs << dc.vrdash_key.to_s
		end
		finalizeVRDashConfigs(vrdcs)

		#Register custom VRLinkedObjects
		vrlos = Array.new
		VRLinkedObject.each do |lo|
			registerVRLinkedObject(lo)
			vrlos << lo.vrlo_key.to_s
		end
		finalizeVRLinkedObjects(vrlos)
	end

	configure :production do
		logputs "Starting Vulnreport in PRODUCTION Environment"
		set :force_ssl, true

		@scheduler = Rufus::Scheduler.new
		VRCron.each do |cron|
			registerVRCron(cron, @scheduler)
		end
	end

	configure :development do
		logputs "WARNING: RUNNING IN DEVELOPMENT ENVIRONMENT"
		logputs "Dev environment: CRON JOBS SCHEDULER NOT ENABLED"

		@scheduler = Rufus::Scheduler.new
		VRCron.each do |cron|
			registerVRCron(cron, @scheduler, false)
		end
	end

	helpers VulnreportAuth
	helpers do
	  include Rack::Utils

	  alias_method :h, :escape_html

	  def csrf_token
	  	Rack::Csrf.csrf_token(env)
	  end

	  def csrf_tag
	  	Rack::Csrf.csrf_tag(env)
	  end
	end

	before do
		@request_ip = request.ip

		if(getSetting('IP_RESTRICTIONS_ON') == 'true')
			ip_allow = getSetting('IP_RESTRICTIONS_ALLOWED')
			
			if(!requestIPAllowed?(@request_ip, ip_allow))
				logputs "IP address #{request.ip} does not match IP Access Restriction rules (#{ip_allow}) - REQUEST BLOCKED"
				halt 401, "IP Access Restrictions do not allow access to Vulnreport from this IP address"
			end
		end

		@session = session
		@VRURL = settings.vrurl
		@VRNAME = settings.vrname
		@VRFOOTER = settings.vrfooter

		if(session[:geo].nil?)
			@geo = GEO::USA
		else
			@geo = session[:geo]
		end

		# Basic perm/auth checks based on route
		if (!request.path_info.start_with?("/saml") && !(request.path_info == "/login" || request.path_info == "/login/"))
			protected!
		end

		if (request.path_info.start_with?("/admin"))
			only_admins!
		end

		if(request.path_info.start_with?("/reviews") || request.path_info.start_with?("/tests") || request.path_info.start_with?("/download") || request.path_info.start_with?("/cx"))
			only_verified!
			no_reporters!
		end

		if request.path_info.start_with?("/reports")
			halt 401, (erb :unauth) if(!canUseReports?)
		end

		if(request.path_info.start_with?("/auditMonitors"))
			halt 401, (erb :unauth) if(!canAuditMonitors?)
		end

		@bhthumb = Application.count

		@user_notifs = Notification.forUser(@session[:uid])
		@unaudited_mts = AuditRecord.count(:reviewed => false, :event_type => MONITOR_EVENT_TYPES)
	end

	# Adapter around the default RequestDataExtractor
	class RequestDataExtractor
		include Rollbar::RequestDataExtractor
		def from_rack(env)
			extract_request_data_from_rack(env).merge({
				:route => env["PATH_INFO"]
			})
		end
	end

	error do
		request_data = RequestDataExtractor.new.from_rack(env)
		uinfo = {
			:id => session[:uid],
			:username => session[:username],
			:email => session[:email]
		}
		#Rollbar.error(env['sinatra.error'], request_data, :user_info => uinfo)
		Rollbar.report_exception(env['sinatra.error'], request_data, uinfo)

		@errstr = "Something went wrong during this request (uncaught exception). The error has been logged and an alert has been sent. It will be debugged ASAP."
		erb :error
	end

	not_found do
		uinfo = {
			:id => session[:uid],
			:username => session[:username],
			:email => session[:email]
		}

		Rollbar.scoped({:person => uinfo}) do
			Rollbar.warning("404 - Route Not Found", {:route => request.path_info, :referrer => request.referrer})
		end
		
		@errstr = "Vulnreport was unable to find a route to handle this request. The error has been logged and an alert has been sent. It will be debugged ASAP."
		erb :error
	end

	######################
	# APPLICATION ROUTES #
	######################

	show_dash = lambda do |dcid|
		cache = true
		if(params['cacheref'] == '1')
			cache = false
		end

		#Values needed for page navigation and style
		@contractors = Organization.all(:contractor => true)
		@user = User.get(session[:uid])

		if(!@user.verified?)
			return erb :unverified
		end

		@allocModalOn = (getSetting('ALLOC_WARN_MODAL') == 'true')

		# Dash components
		# => @panels is array of hashes, each hash being panel components (title, records, hasbulkptc, zerotext, fetch_time). Rendered top-down in order
		# => @statblocks is an array of 4 hashes (block_#), each hash being stat block info (icon, value, color). Rendered left-right in order
		@panels = Array.new
		@statblocks = Array.new

		geos = @geo
		if(geos == 0)
			geos = GEO.constants.map{|e| GEO.const_get(e)}
		end

		@dashId = dcid
		@dashOptions = DashConfig.all(:active => true)

		# Default dashboard is its own case
		if(dcid == 0)
			defaultPanels = [{:title => "My Active Reviews", :color => "primary", :type => DASHPANEL_TYPE::MYACTIVE, :maxwks => 0, :zerotext => "No Records"},
							 {:title => "My New Reviews", :color => "primary", :type => DASHPANEL_TYPE::MY_WNO_TESTS, :maxwks => 0, :zerotext => "No Records"},
							 {:title => "My Pending Approvals", :color => "primary", :type => DASHPANEL_TYPE::MY_APPROVALS, :maxwks => 0, :zerotext => "No Records"}]
			dc = DashConfig.new(:name => "Default Dashboard", :showStats => false, :customCode => false, :panels => defaultPanels)
			@dashName = "Default Dashboard"
		else
			dc = DashConfig.get(dcid)
			@dashName = dc.name
		end

		if(dc.customCode)
			dashSubclass = VRDashConfig.getByKey(dc.customKey)
			if(dashSubclass.nil?)
				Rollbar.error("Custom DC subclass missing", {:DCID => dc.id, :Key => dc.customKey})
				@errstr = "Unable to generate dashboard - subclass missing"
				return erb :error
			end

			begin
				dashResult = dashSubclass.generate(dc.getSettingsForDash, @user.id, geos, cache)
			rescue Exception => e
				dashResult = {:success => false, :faultstring => "Exception occurred while generating dashboard"}
				Rollbar.error(e, "Exception while generating custom dashboard", {:uid => @user.id, :dc_key => dc.customKey})
			end

			if(dashResult[:success])
				@panels, @statblocks = dashResult[:generatedDash]
				if(!@statblocks.nil?)
					@showStats = true
				end
			else
				Rollbar.error("DC generate failure", {:DCID => dc.id, :Key => dc.customKey, :fault => dashResult[:faultstring]})
				@dashError = true
				@errstr = "Unable to generate dashboard - #{dashResult[:faultstring]}"
				return erb :dash
			end
		else
			#First build the panels, *respecting permissions over all else*
			dc.panels.each do |panel|
				records = Array.new
				addedThisPanel = Array.new

				#Check RT access first
				if(!getAllowedRTsForUser(@user.id).include?(panel[:rt].to_i) && !NON_RT_DASHPANELS.include?(panel[:type]))
					records = []
				elsif(panel[:type] == DASHPANEL_TYPE::MYACTIVE)
					Test.all(:reviewer => session[:uid], :complete => false, Test.application.geo => geos).each do |t|
						next if(addedThisPanel.include?(t.application_id))
						a = Application.get(t.application_id)
						next if (a.isPrivate && !canViewReview?(a.id))
						
						records << {:app => a, :test => t}
						addedThisPanel << a.id
					end
				elsif(panel[:type] == DASHPANEL_TYPE::MYACTIVE_RT)
					Test.all(Test.application.record_type => panel[:rt], :reviewer => session[:uid], :complete => false, Test.application.geo => geos).each do |t|
						next if(addedThisPanel.include?(t.application_id))
						a = Application.get(t.application_id)
						next if (a.isPrivate && !canViewReview?(a.id))
						
						records << {:app => a, :test => t}
						addedThisPanel << a.id
					end
				elsif(panel[:type] == DASHPANEL_TYPE::MY_WNO_TESTS)
					Application.all(:owner => session[:uid], :tests => nil, :geo => geos).each do |a|
						next if(addedThisPanel.include?(a.id))
						next if (a.isPrivate && !canViewReview?(a.id))
						records << {:app => a, :test => nil}
						addedThisPanel << a.id
					end
				elsif(panel[:type] == DASHPANEL_TYPE::MY_WNO_TESTS_RT)
					Application.all(:record_type => panel[:rt], :owner => session[:uid], :tests => nil, :geo => geos).each do |a|
						next if(addedThisPanel.include?(a.id))
						next if (a.isPrivate && !canViewReview?(a.id))
						records << {:app => a, :test => nil}
						addedThisPanel << a.id
					end
				elsif(panel[:type] == DASHPANEL_TYPE::STATUS_NEW_AND_INPROG)
					Test.all(Test.application.record_type => panel[:rt], :complete => false, Test.application.geo => geos).each do |t|
						next if(addedThisPanel.include?(t.application_id))
						a = Application.get(t.application_id)
						next if (a.isPrivate && !canViewReview?(a.id))
						
						records << {:app => a, :test => t}
						addedThisPanel << a.id
					end
				elsif(panel[:type] == DASHPANEL_TYPE::STATUS_PASSED)
					Test.all(Test.application.record_type => panel[:rt], :complete => true, :pass => true, Test.application.geo => geos).each do |t|
						next if(addedThisPanel.include?(t.application_id))
						a = Application.get(t.application_id)
						next if (a.isPrivate && !canViewReview?(a.id))
						
						#Only care about most recent test as it is app's status
						next if(t.id != a.tests.last.id)

						records << {:app => a, :test => t}
						addedThisPanel << a.id
					end
				elsif(panel[:type] == DASHPANEL_TYPE::STATUS_FAILED)
					Test.all(Test.application.record_type => panel[:rt], :complete => true, :pass => false, Test.application.geo => geos).each do |t|
						next if(addedThisPanel.include?(t.application_id))
						a = Application.get(t.application_id)
						next if (a.isPrivate && !canViewReview?(a.id))

						#Only care about most recent test as it is app's status
						next if(t.id != a.tests.last.id)

						records << {:app => a, :test => t}
						addedThisPanel << a.id
					end
				elsif(panel[:type] == DASHPANEL_TYPE::STATUS_CLOSED)
					Test.all(Test.application.record_type => panel[:rt], :complete => true, Test.application.geo => geos).each do |t|
						next if(addedThisPanel.include?(t.application_id))
						a = Application.get(t.application_id)
						next if (a.isPrivate && !canViewReview?(a.id))

						#Only care about most recent test as it is app's status
						next if(t.id != a.tests.last.id)

						records << {:app => a, :test => t}
						addedThisPanel << a.id
					end
				elsif(panel[:type] == DASHPANEL_TYPE::ALL_APPS)
					Application.all(:record_type => panel[:rt], :geo => geos).each do |a|
						next if(addedThisPanel.include?(a.id))
						next if (a.isPrivate && !canViewReview?(a.id))
						records << {:app => a, :test => nil}
						addedThisPanel << a.id
					end
				elsif(panel[:type] == DASHPANEL_TYPE::APPS_WNO_TESTS)
					Application.all(:record_type => panel[:rt], :geo => geos).each do |a|
						next if(addedThisPanel.include?(a.id))
						next if (a.tests.size > 0)
						next if (a.isPrivate && !canViewReview?(a.id))
						records << {:app => a, :test => nil}
						addedThisPanel << a.id
					end
				elsif(panel[:type] == DASHPANEL_TYPE::UNASSIGNED_NEW_RT)
					Application.all(:record_type => panel[:rt], :geo => geos, :owner => nil).each do |a|
						next if(addedThisPanel.include?(a.id))
						next if (a.tests.size > 0)
						next if (a.isPrivate && !canViewReview?(a.id))
						records << {:app => a, :test => nil}
						addedThisPanel << a.id
					end
				elsif(panel[:type] == DASHPANEL_TYPE::UNASSIGNED_NEW_ALL)
					Application.all(:geo => geos, :owner => nil).each do |a|
						next if(addedThisPanel.include?(a.id))
						next if (a.tests.size > 0)
						next if (a.isPrivate && !canViewReview?(a.id))
						records << {:app => a, :test => nil}
						addedThisPanel << a.id
					end
				elsif(panel[:type] == DASHPANEL_TYPE::MY_PASSED)
					Test.all(:reviewer => session[:uid], :complete => true, :pass => true, Test.application.geo => geos).each do |t|
						next if(addedThisPanel.include?(t.application_id))
						a = Application.get(t.application_id)
						next if (a.isPrivate && !canViewReview?(a.id))

						#Only care about most recent test as it is app's status
						next if(t.id != a.tests.last.id)
						
						records << {:app => a, :test => t}
						addedThisPanel << a.id
					end
				elsif(panel[:type] == DASHPANEL_TYPE::MY_FAILED)
					Test.all(:reviewer => session[:uid], :complete => true, :pass => false, Test.application.geo => geos).each do |t|
						next if(addedThisPanel.include?(t.application_id))
						a = Application.get(t.application_id)
						next if (a.isPrivate && !canViewReview?(a.id))

						#Only care about most recent test as it is app's status
						next if(t.id != a.tests.last.id)
						
						records << {:app => a, :test => t}
						addedThisPanel << a.id
					end
				elsif(panel[:type] == DASHPANEL_TYPE::MY_ALL)
					Test.all(:reviewer => session[:uid], :complete => true, Test.application.geo => geos).each do |t|
						next if(addedThisPanel.include?(t.application_id))
						a = Application.get(t.application_id)
						next if (a.isPrivate && !canViewReview?(a.id))

						#Only care about most recent test as it is app's status
						next if(t.id != a.tests.last.id)
						
						records << {:app => a, :test => t}
						addedThisPanel << a.id
					end
				elsif(panel[:type] == DASHPANEL_TYPE::MY_APPROVALS)
					Test.all(:is_pending => true, Test.application.geo => geos).each do |t|
						next if(addedThisPanel.include?(t.application_id))
						a = Application.get(t.application_id)
						next if (a.isPrivate && !canViewReview?(a.id))

						next if !canFinalizeTest?(t.id)
						
						records << {:app => a, :test => t}
						addedThisPanel << a.id
					end

					if(canApproveProvPass?)
						Test.all(:complete => false, :provPassReq => true, :provPass => false).each do |t|
							next if(addedThisPanel.include?(t.application_id))

							if(getAllowedRTsForUser(@session[:uid]).include?(t.application.record_type))
								a = Application.get(t.application_id)
								next if (a.isPrivate && !canViewReview?(a.id))
								next if !canFinalizeTest?(t.id)

								records << {:app => a, :test => t}
								addedThisPanel << a.id
							end
						end
					end
				elsif(panel[:type] == DASHPANEL_TYPE::MY_APPROVALS)
					Test.all(:is_pending => true, Test.application.record_type => panel[:rt], Test.application.geo => geos).each do |t|
						next if(addedThisPanel.include?(t.application_id))
						a = Application.get(t.application_id)
						next if (a.isPrivate && !canViewReview?(a.id))

						next if !canFinalizeTest?(t.id)
						
						records << {:app => a, :test => t}
						addedThisPanel << a.id
					end

					if(canApproveProvPass?)
						Test.all(:complete => false, :provPassReq => true, :provPass => false, Test.application.record_type => panel[:rt]).each do |t|
							next if(addedThisPanel.include?(t.application_id))

							if(getAllowedRTsForUser(@session[:uid]).include?(t.application.record_type))
								a = Application.get(t.application_id)
								next if (a.isPrivate && !canViewReview?(a.id))
								next if !canFinalizeTest?(t.id)

								records << {:app => a, :test => t}
								addedThisPanel << a.id
							end
						end
					end
				end

				@panels << {:title => panel[:title], :color => panel[:color], :records => records, :maxwks => ((panel[:maxwks] <= 0) ? nil : panel[:maxwks]),
							:fetch_time => nil, :zerotext => panel[:zerotext], :panelType => panel[:type], :panelRT => panel[:rt]}
			end

			#Build stats
			if(dc.showStats)
				@showStats = true
				dc.stats.each do |stat|
					count = 0
					addedThisPanel = Array.new

					#First, see if there is an identical panel to just get its size instead of recreating queries
					isPanelDup = false
					@panels.each do |panel|
						if(stat[:type] == panel[:panelType] && stat[:rt] == panel[:panelRT])
							isPanelDup = true
							count = panel[:records].size
						end
					end

					#Not a panel dup, so do some calculating. Same as above, but we will only care about the count.
					# We have to actually do full db queries to check perms, last status, and duplication
					if(!isPanelDup)
						if(!getAllowedRTsForUser(@user.id).include?(stat[:rt].to_i) && stat[:type] != DASHPANEL_TYPE::MYACTIVE)
							count = 0
						elsif(stat[:type] == DASHPANEL_TYPE::MYACTIVE)
							Test.all(:reviewer => session[:uid], :complete => false, Test.application.geo => geos).each do |t|
								next if(addedThisPanel.include?(t.application_id))
								a = Application.get(t.application_id)
								next if (a.isPrivate && !canViewReview?(a.id))
								
								count += 1
								addedThisPanel << a.id
							end
						elsif(stat[:type] == DASHPANEL_TYPE::MYACTIVE_RT)
							Test.all(Test.application.record_type => stat[:rt], :reviewer => session[:uid], :complete => false, Test.application.geo => geos).each do |t|
								next if(addedThisPanel.include?(t.application_id))
								a = Application.get(t.application_id)
								next if (a.isPrivate && !canViewReview?(a.id))
								
								count += 1
								addedThisPanel << a.id
							end
						elsif(stat[:type] == DASHPANEL_TYPE::MY_WNO_TESTS)
							Application.all(:reviewer => session[:uid], :tests => nil, :geo => geos).each do |a|
								next if(addedThisPanel.include?(a.id))
								next if (a.isPrivate && !canViewReview?(a.id))
								
								count += 1
								addedThisPanel << a.id
							end
						elsif(stat[:type] == DASHPANEL_TYPE::MY_WNO_TESTS_RT)
							Application.all(:record_type => stat[:rt], :reviewer => session[:uid], :tests => nil, :geo => geos).each do |a|
								next if(addedThisPanel.include?(a.id))
								next if (a.isPrivate && !canViewReview?(a.id))
								
								count += 1
								addedThisPanel << a.id
							end
						elsif(stat[:type] == DASHPANEL_TYPE::STATUS_NEW_AND_INPROG)
							Test.all(Test.application.record_type => stat[:rt], :complete => false, Test.application.geo => geos).each do |t|
								next if(addedThisPanel.include?(t.application_id))
								a = Application.get(t.application_id)
								next if (a.isPrivate && !canViewReview?(a.id))
								
								count += 1
								addedThisPanel << a.id
							end
						elsif(stat[:type] == DASHPANEL_TYPE::STATUS_PASSED)
							Test.all(Test.application.record_type => stat[:rt], :complete => true, :pass => true, Test.application.geo => geos).each do |t|
								next if(addedThisPanel.include?(t.application_id))
								a = Application.get(t.application_id)
								next if (a.isPrivate && !canViewReview?(a.id))
								
								#Only care about most recent test as it is app's status
								next if(t.id != a.tests.last.id)

								count += 1
								addedThisPanel << a.id
							end
						elsif(stat[:type] == DASHPANEL_TYPE::STATUS_FAILED)
							Test.all(Test.application.record_type => stat[:rt], :complete => true, :pass => false, Test.application.geo => geos).each do |t|
								next if(addedThisPanel.include?(t.application_id))
								a = Application.get(t.application_id)
								next if (a.isPrivate && !canViewReview?(a.id))

								#Only care about most recent test as it is app's status
								next if(t.id != a.tests.last.id)

								count += 1
								addedThisPanel << a.id
							end
						elsif(stat[:type] == DASHPANEL_TYPE::STATUS_CLOSED)
							Test.all(Test.application.record_type => stat[:rt], :complete => true, Test.application.geo => geos).each do |t|
								next if(addedThisPanel.include?(t.application_id))
								a = Application.get(t.application_id)
								next if (a.isPrivate && !canViewReview?(a.id))

								#Only care about most recent test as it is app's status
								next if(t.id != a.tests.last.id)

								count += 1
								addedThisPanel << a.id
							end
						elsif(stat[:type] == DASHPANEL_TYPE::ALL_APPS)
							Application.all(:record_type => stat[:rt], :geo => geos).each do |a|
								next if(addedThisPanel.include?(a.id))
								next if (a.isPrivate && !canViewReview?(a.id))
								count += 1
								addedThisPanel << a.id
							end
						elsif(stat[:type] == DASHPANEL_TYPE::APPS_WNO_TESTS)
							Application.all(:record_type => stat[:rt], :geo => geos).each do |a|
								next if(addedThisPanel.include?(a.id))
								next if (a.tests.size > 0)
								next if (a.isPrivate && !canViewReview?(a.id))
								count += 1
								addedThisPanel << a.id
							end
						elsif(stat[:type] == DASHPANEL_TYPE::UNASSIGNED_NEW_RT)
							Application.all(:record_type => stat[:rt], :geo => geos, :owner => nil).each do |a|
								next if(addedThisPanel.include?(a.id))
								next if (a.tests.size > 0)
								next if (a.isPrivate && !canViewReview?(a.id))
								count += 1
								addedThisPanel << a.id
							end
						elsif(stat[:type] == DASHPANEL_TYPE::UNASSIGNED_NEW_ALL)
							Application.all(:geo => geos, :owner => nil).each do |a|
								next if(addedThisPanel.include?(a.id))
								next if (a.tests.size > 0)
								next if (a.isPrivate && !canViewReview?(a.id))
								count += 1
								addedThisPanel << a.id
							end
						elsif(stat[:type] == DASHPANEL_TYPE::MY_PASSED)
							Test.all(:reviewer => session[:uid], :complete => true, :pass => true, Test.application.geo => geos).each do |t|
								next if(addedThisPanel.include?(t.application_id))
								a = Application.get(t.application_id)
								next if (a.isPrivate && !canViewReview?(a.id))

								#Only care about most recent test as it is app's status
								next if(t.id != a.tests.last.id)
								
								count += 1
								addedThisPanel << a.id
							end
						elsif(stat[:type] == DASHPANEL_TYPE::MY_FAILED)
							Test.all(:reviewer => session[:uid], :complete => true, :pass => false, Test.application.geo => geos).each do |t|
								next if(addedThisPanel.include?(t.application_id))
								a = Application.get(t.application_id)
								next if (a.isPrivate && !canViewReview?(a.id))

								#Only care about most recent test as it is app's status
								next if(t.id != a.tests.last.id)
								
								count += 1
								addedThisPanel << a.id
							end
						elsif(stat[:type] == DASHPANEL_TYPE::MY_ALL)
							Test.all(:reviewer => session[:uid], :complete => true, Test.application.geo => geos).each do |t|
								next if(addedThisPanel.include?(t.application_id))
								a = Application.get(t.application_id)
								next if (a.isPrivate && !canViewReview?(a.id))

								#Only care about most recent test as it is app's status
								next if(t.id != a.tests.last.id)
								
								count += 1
								addedThisPanel << a.id
							end
						elsif(stat[:type] == DASHPANEL_TYPE::MY_APPROVALS)
							Test.all(:is_pending => true, Test.application.geo => geos).each do |t|
								next if(addedThisPanel.include?(t.application_id))
								a = Application.get(t.application_id)
								next if (a.isPrivate && !canViewReview?(a.id))

								next if !canFinalizeTest?(t.id)
								
								count += 1
								addedThisPanel << a.id
							end

							if(canApproveProvPass?)
								Test.all(:complete => false, :provPassReq => true, :provPass => false).each do |t|
									next if(addedThisPanel.include?(t.application_id))

									if(getAllowedRTsForUser(@session[:uid]).include?(t.application.record_type))
										a = Application.get(t.application_id)
										next if (a.isPrivate && !canViewReview?(a.id))
										next if !canFinalizeTest?(t.id)

										count += 1
										addedThisPanel << a.id
									end
								end
							end
						elsif(stat[:type] == DASHPANEL_TYPE::MY_APPROVALS_RT)
							Test.all(:is_pending => true, Test.application.record_type => stat[:rt], Test.application.geo => geos).each do |t|
								next if(addedThisPanel.include?(t.application_id))
								a = Application.get(t.application_id)
								next if (a.isPrivate && !canViewReview?(a.id))

								next if !canFinalizeTest?(t.id)
								
								count += 1
								addedThisPanel << a.id
							end

							if(canApproveProvPass?)
								Test.all(:complete => false, :provPassReq => true, :provPass => false, Test.application.record_type => stat[:rt]).each do |t|
									next if(addedThisPanel.include?(t.application_id))

									if(getAllowedRTsForUser(@session[:uid]).include?(t.application.record_type))
										a = Application.get(t.application_id)
										next if (a.isPrivate && !canViewReview?(a.id))
										next if !canFinalizeTest?(t.id)

										count += 1
										addedThisPanel << a.id
									end
								end
							end
						end
					end

					color = stat[:color]
					if(color.start_with?("auto"))
						lim = color[4..5].to_i
						if(count < lim)
							color = "success"
						elsif(count < lim*2)
							color = "warning"
						else
							color = "danger"
						end
					end

					@statblocks << {:icon => stat[:icon], :text => stat[:text], :value => count, :color => color}
				end

			else
				@showStats = false
			end
		end
		
		erb :dash
	end

	##
	# Main index page - dashboard.
	# @route /
	# @viewfile views/dash.erb
	get '/' do
		@user = User.get(session[:uid])

		#What dash config are we using?
		if(@user.dashOverride >= 0)
			dcid = @user.dashOverride
		else
			if(!@user.verified?)
				dcid = 0
			else
				org = Organization.get(@user.org)
				if(org.nil?)
					dcid = 0
				else
					dcid = org.dashconfig
				end
			end
		end

		if(dcid > 0)
			dc = DashConfig.get(dcid)
			dcid = 0 if(dc.nil?)
		end

		instance_exec dcid, &show_dash
	end

	get '/showdash/:dcid/?' do
		dcid = params[:dcid].to_i

		dc = DashConfig.get(dcid)
		dcid == 0 if(dc.nil?)

		instance_exec dcid, &show_dash
	end

	get "/geo/:geo/?" do
		session[:geo] = params[:geo].to_i
		redirect "/"
	end

	post "/postcomment/:what/:whatid/?" do
		what = nil
		whatId = nil

		if(params[:what] == "a")
			app = Application.get(params[:whatid])
			if(app.nil?)
				@errstr = "App not found"
				return erb :error 
			end
			halt 401, (erb :unauth) if(!canViewReview?(app.id))

			what = LINK_TYPE::APPLICATION
			whatId = app.id
		elsif(params[:what] == "t")
			test = Test.get(params[:whatid])
			if(test.nil?)
				@errstr = "Test not found"
				return erb :error 
			end
			app = test.application
			halt 401, (erb :unauth) if(!canViewReview?(app.id))

			what = LINK_TYPE::TEST
			whatId = test.id
		elsif(params[:what] == "v")
			vuln = Vulnerability.get(params[:whatid])
			if(vuln.nil?)
				@errstr = "Vuln not found"
				return erb :error 
			end
			test = vuln.test
			app = test.application
			halt 401, (erb :unauth) if(!canViewReview?(app.id))

			what = LINK_TYPE::VULN
			whatId = vuln.id
		end

		if(what.nil? || whatId.nil?)
			@errstr = "No What/WhatID to post comment"
			return erb :error
		end

		body = params[:body].strip
		vis_myOrg = false
		if (!params[:vis_myOrg].nil?)
			vis_myOrg = true
		end

		vis_tester = false
		if (!params[:vis_tester].nil?)
			vis_tester = true
		end

		vis_testOrg = false
		if (!params[:vis_testOrg].nil?)
			vis_testOrg = true
		end

		if(body.nil? || body.empty?)
			redirect "/tests/#{test.id}/#{vuln.id}"
		else
			c = Comment.create(:what => what, :whatId => whatId, :body => body, :author => session[:uid], :views => [session[:uid]], :vis_authOrg => vis_myOrg, :vis_tester => vis_tester, :vis_testOrg => vis_testOrg)
		end

		if(what == LINK_TYPE::APPLICATION)
			redirect "/reviews/#{whatId}"
		elsif(what == LINK_TYPE::TEST)
			redirect "/tests/#{whatId}"
		elsif(what == LINK_TYPE::VULN)
			redirect "/tests/#{test.id}/#{whatId}"
		end
	end

	post "/markCommentsRead/:what/:whatid/?" do
		what = nil
		whatId = nil

		if(params[:what] == "a")
			app = Application.get(params[:whatid])
			if(app.nil?)
				@errstr = "App not found"
				return erb :error 
			end
			halt 401, (erb :unauth) if(!canViewReview?(app.id))

			comments = Comment.commentsForApp(params[:whatid], session[:uid], session[:org])
		elsif(params[:what] == "t")
			test = Test.get(params[:whatid])
			if(test.nil?)
				@errstr = "Test not found"
				return erb :error 
			end
			app = test.application
			halt 401, (erb :unauth) if(!canViewReview?(app.id))

			comments = Comment.commentsForTest(params[:whatid], session[:uid], session[:org])
		elsif(params[:what] == "v")
			vuln = Vulnerability.get(params[:whatid])
			if(vuln.nil?)
				@errstr = "Vuln not found"
				return erb :error 
			end
			test = vuln.test
			app = test.application
			halt 401, (erb :unauth) if(!canViewReview?(app.id))

			comments = Comment.commentsForVuln(params[:whatid], session[:uid], session[:org])
		end

		comments.each do |c|
			if(c.isUnseen?(session[:uid]))
				c.markSeen(session[:uid])
			end
		end

		return 200
	end

	post "/markNotifsSeen/?" do
		Notification.markAllUserRead(session[:uid])
		return 200
	end

	get "/viewAllNotifs/?" do
		@notifs = Notification.allForUser(session[:uid])
		Notification.markAllUserRead(session[:uid])

		erb :view_all_notifs
	end

	post "/delComment/:cid/?" do
		c = Comment.get(params[:cid].to_i)
		if(c.author != session[:uid] && !admin?)
			return 401
		else
			if(c.destroy)
				return 200
			else
				return 500
			end
		end
	end

	get '/usersettings' do
		@user = User.get(session[:uid])
		@pageTitle = "User Settings"

		userAlloc = MonthlyAllocation.allocationForUser(@user.id)
		if(userAlloc.nil?)
			@alloc = 0
		else
			@alloc = userAlloc.allocation
		end

		@dashConfigs = DashConfig.all(:active => true)

		erb :usersettings
	end

	post '/usersettings' do
		if(!params[:save].nil?)
			@user = User.get(session[:uid])

			newName = params[:userName].strip
			@user.name = newName unless newName.nil?

			newInits = params[:userInitials].strip
			@user.initials = newInits unless newInits.nil?

			newEmail = params[:email].strip
			@user.email = newEmail unless (newEmail.nil? || !isValidEmail?(newEmail))

			newExtEID = params[:user_ext_eid].strip
			@user.extEID = newExtEID unless newExtEID.nil?

			@user.dashOverride = params[:dashConfig].to_i

			newGeo = params[:userGeo].to_i
			@user.defaultGeo = newGeo unless newGeo == 0

			newAlloc = params[:userAlloc].to_i
			userAlloc = MonthlyAllocation.setAllocationForUser(@user.id, newAlloc)
			
			@alloc = userAlloc.allocation
			@dashConfigs = DashConfig.all(:active => true)

			@pageTitle = "User Settings"
			if(@user.save)
				session[:name] = newName unless newName.nil?
				session[:firstname] = newName.split(" ").first unless newName.nil?
				session[:initials] = newInits unless newInits.nil?
				session[:email] = newEmail unless (newEmail.nil? || !isValidEmail?(newEmail))
				session[:geo] = newGeo unless newGeo == 0
				@saved = true
				erb :usersettings
			else
				@save_error = true
				erb :usersettings
			end
		end
	end

	get '/usersettings/auth/?' do
		@user = User.get(session[:uid])
		@pageTitle = "User Settings"

		erb :usersettings_auth
	end

	post '/usersettings/auth/?' do
		@user = User.get(session[:uid])
		@pageTitle = "User Settings"

		if(getSetting('AUTH_SSO_ENABLED') == 'true')
			#Nothing to do here since user can't update
		end

		if(getSetting('AUTH_LOGIN_ENABLED') == 'true')
			pwlen = getSetting("AUTH_LOGIN_PWLEN").to_i
			if(pwlen == 0)
				pwlen = 8
			end

			cur = params[:login_current_password]
			pass = params[:login_password]
			conf = params[:login_password_conf]

			if(!@user.password.nil? && (@user.password != cur))
				@save_error = true
				@save_error_str = "Invalid Password"
			elsif(pass != conf)
				@save_error = true
				@save_error_str = "Password and confirmation do not match"
			elsif(pass.length < pwlen)
				@save_error = true
				@save_error_str = "Password must be at least #{pwlen} characters"
			else
				@user.password = pass
				if(@user.save)
					@saved = true
				else
					@save_error = true
					@save_error_str = @user.errors.inspect
				end
			end
		end

		erb :usersettings_auth
	end

	get '/userdash/?' do
		@pageTitle = "User Dashboard"
		month = params['m'].to_i
		year = params['y'].to_i

		if(month.nil? || year.nil? || year < 2014 || year > 2025 || month < 1 || month > 12)
			@date = Date.today.at_beginning_of_month
		else
			@date = Date.new(year, month, 1)
		end

		@user = User.get(session[:uid])

		userAlloc = MonthlyAllocation.allocationForUser(@user.id, month=@date.month, year=@date.year)
		if(userAlloc.nil?)
			@alloc = 0
			@allocNil = true
			@autoSet = false
		else
			@alloc = userAlloc.allocation
			@autoSet = userAlloc.wasAutoSet
			@allocNil = false
		end

		@allocApps = (((@user.allocCoeff.to_f)/12.0)*(@alloc.to_f/100.0)).round

		@numTests = 0
		@appsTouched = Array.new
		endDate = @date >> 1
		Test.all(:reviewer => @user.id, :complete => true, :closed_at => (@date..endDate)).each do |t|
			@numTests += 1
			if(!@appsTouched.include?(t.application_id))
				@appsTouched << t.application_id
			end
		end

		@pbWidth = 0
		@allocCompletionPct = 0
		if(@appsTouched.size > 0)
			@allocCompletionPct = ((@appsTouched.size.to_f / @allocApps.to_f)*100)
			if(@appsTouched.size > 0 && @allocApps == 0)
				@pbWidth = 100
			else
				@pbWidth = @allocCompletionPct.round
				@pbWidth = 100 if @pbWidth > 100
			end
		end

		## LIFETIME STATS ##
		@lifetimeTests = 0
		@lifetimePass = 0
		@lifetimeFail = 0
		@lifetimeAppsTouched = Array.new
		@lifetimeVulns = Array.new

		@lifetimeMaxTestTime = 0
		@lifetimeMaxTest = nil
		@lifetimeMinTestTime = 0
		@lifetimeMinTest = nil

		lifetimeTotalTestDays = 0

		Test.all(:reviewer => @user.id, :complete => true).each do |t|
			@lifetimeTests += 1
			if(t.pass)
				@lifetimePass += 1
			else
				@lifetimeFail += 1
			end

			if(!@lifetimeAppsTouched.include?(t.application_id))
				@lifetimeAppsTouched << t.application_id
			end

			@lifetimeVulns.push(*t.vulnerabilities)

			if(!t.closed_at.nil? && !t.created_at.nil?)
				testDays = t.closed_at - t.created_at
				lifetimeTotalTestDays += testDays
				if(testDays > @lifetimeMaxTestTime)
					@lifetimeMaxTestTime = testDays
					@lifetimeMaxTest = t
				end
				if(testDays < @lifetimeMinTestTime || @lifetimeMinTestTime == 0)
					@lifetimeMinTestTime = testDays
					@lifetimeMinTest = t
				end
			end

			@lifetimeTTRAvg = (lifetimeTotalTestDays.to_f / @lifetimeTests.to_f)
		end

		if(@lifetimeTests < 1)
			@lifetimePassPct = 0
			@lifetimeFailPct = 0
			@lifetimeTTRAvg = 0
		else
			@lifetimePassPct = (@lifetimePass.to_f / @lifetimeTests.to_f)*100
			@lifetimeFailPct = (@lifetimeFail.to_f / @lifetimeTests.to_f)*100
		end

		#top 5 vuln types and counts
		vulnTypeCounts = Array.new(VulnType.count()+1, 0)
		@lifetimeVulns.each do |v|
			next if(v.vulntype == 0)
			vulnTypeCounts[v.vulntype] += 1
		end

		sortedIdx = vulnTypeCounts.map.with_index.sort{|x, y| y <=> x}.map(&:last)[0..4]
		@topVulns = Array.new
		@maxTopVulnCount = vulnTypeCounts[sortedIdx[0]]
		sortedIdx.each do |i|
			next if(i < 1)
			next if vulnTypeCounts[i] == 0
			@topVulns << {:vtid => i, :vt => h(VulnType.get(i).name), :count => vulnTypeCounts[i]}
		end

		erb :userdash
	end

	get "/userDirectsDash/?" do
		@directs = User.all(:manager_id => @session[:uid])

		if(!isManager? || @directs.nil?)
			@errstr = "No direct reports"
			return erb :error
		end

		@data = Hash.new
		@directs.each do |u|
			@data[u.id] = Hash.new
			monthStartDate = Date.today.at_beginning_of_month
			monthEndDate = monthStartDate >> 1
			fyStartDate = Date.new((fy(Date.today).to_i)-1, 2, 1)
			fyEndDate = Date.new((fy(Date.today).to_i), 1, 31)

			testsThisReviewer = 0
			appsThisReviewer = Array.new
			Test.all(:reviewer => u.id, :complete => true, :closed_at => (monthStartDate..monthEndDate)).each do |t|
				testsThisReviewer += 1
				if(!appsThisReviewer.include?(t.application_id))
					appsThisReviewer << t.application_id
				end
			end

			@data[u.id][:uniqueAppsMonth] = appsThisReviewer.size
			@data[u.id][:numTestsMonth] = testsThisReviewer

			testsThisReviewer = 0
			appsThisReviewer = Array.new
			Test.all(:reviewer => u.id, :complete => true, :closed_at => (fyStartDate..fyEndDate)).each do |t|
				testsThisReviewer += 1
				if(!appsThisReviewer.include?(t.application_id))
					appsThisReviewer << t.application_id
				end
			end

			@data[u.id][:uniqueAppsFY] = appsThisReviewer.size
			@data[u.id][:numTestsFY] = testsThisReviewer
		end

		erb :user_directs_dash
	end

	post "/userDirectsDash/?" do
		@directs = User.all(:manager_id => @session[:uid])

		if(!isManager? || @directs.nil?)
			@errstr = "No direct reports"
			return erb :error
		end

		@directs.each do |u|
			newUseAlloc = (!params[:"useAlloc_#{u.id}"].nil?)
			newAllocCoeff = params[:"allocCoeff_#{u.id}"].to_i
			if(newAllocCoeff <= 0)
				newAllocCoeff = getSetting('ALLOC_DEFAULT')
				newAllocCoeff = newAllocCoeff.nil? ? User.allocCoeff.default : newAllocCoeff.to_i
			end
			newAllocPct = params[:"curAlloc_#{u.id}"].to_i

			u.useAllocation = newUseAlloc
			if(!newUseAlloc && !u.allocation.nil?)
				ma = MonthlyAllocation.allocationForUser(u.id)
				ma.destroy
			end

			u.allocCoeff = newAllocCoeff
			u.save

			if(u.useAllocation && !u.allocation.nil?)
				ma = MonthlyAllocation.allocationForUser(u.id)
				ma.allocation = newAllocPct
				ma.wasMgrSet = true
				ma.wasAutoSet = false
				ma.save
			elsif(u.useAllocation && u.allocation.nil? && !params[:"curAlloc_#{u.id}"].nil?)
				ma = MonthlyAllocation.setAllocationForUser(u.id, newAllocPct)
				ma.wasMgrSet = true
				ma.save
			end
		end

		redirect "/userDirectsDash"
	end

	###
	# Endpoint to prefetch typeahead data for Bloodhound (used for search bar).
	# Prefetch returns the most recent 250 {Application}s (by creation date). For matches
	# not found in prefetch data, search will hit the /remoteBH endpoint. Return format is JSON.
	# @route /prefetchBH
	get "/prefetchBH/?" do
		if(reports_only?)
			return "[]"
		end

		allowedRTs = getAllowedRTsForUser(@session[:uid])
		apps = Array.new

		Application.all(:record_type => allowedRTs, :order => [ :id.desc ], :limit => 250).each do |a|
			if(a.isPrivate)
				next if(!a.allow_UIDs.nil? && !a.allow_UIDs.include?(@session[:uid]))
			end
			apps << {"name" => a.name, :id => a.id}.to_json
		end

		return "[#{apps.join(",")}]"
	end

	###
	# Bloodhound remote search endpoint. If string in search bar is not found in local (prefetch)
	# data additional results will come from this endpoint.
	# @route /remoteBH/[SEARCH STRING]
	get '/remoteBH/:q/?' do
		q = params[:q]

		if(reports_only?)
			return "[]"
		end

		allowedRTs = getAllowedRTsForUser(@session[:uid])
		apps = Array.new

		Application.all(:record_type => allowedRTs, :order => [ :id.desc ], :name.like => "%#{q}%", :limit => 250).each do |a|
			if(a.isPrivate)
				next if(!a.allow_UIDs.nil? && !a.allow_UIDs.include?(@session[:uid]))
			end
			apps << {"name" => a.name, :id => a.id}.to_json
		end

		return "[#{apps.join(",")}]"
	end

	get '/search/?' do
		if(params[:searchInput].nil? || params[:searchInput].empty?)
			return erb :search
		end

		@q = params[:searchInput]

		@allowedRecordTypesFull = getAllowedRTObjsForUser(@session[:uid])
		@allowedRecordTypes = @allowedRecordTypesFull.map{|rt| rt.id}
		
		if(params[:rt].nil? || params[:rt].to_s.downcase == "all")
			@selectedRecordTypes = @allowedRecordTypes
		else
			@selectedRecordTypes = @allowedRecordTypes & (params[:rt].map{|n| n.to_i})
			@selectedRecordTypes = @allowedRecordTypes if(@selectedRecordTypes.size == 0)
		end

		#Check for an EID match
		eidLink = Link.first(:toType => LINK_TYPE::VRLO, :toId => @q, :fromType => LINK_TYPE::APPLICATION)
		if(!eidLink.nil?)
			#Only do EID redirection if user can see app. Otherwise info leak.
			if(canViewReview?(eidLink.fromId))
				#Redirect to application
				redirect "/reviews/#{eidLink.fromId}"
			end
		end

		@reviewResults = Array.new
		@testResults = Array.new

		@reviewResults = Application.all(:conditions => [ "name ILIKE ?", "%#{@q}%" ], :order => [ :id.desc ], :record_type => @selectedRecordTypes) + Application.all(:conditions => [ "description ILIKE ?", "%#{@q}%" ], :order => [ :id.desc ], :record_type => @selectedRecordTypes)
		@testResults = Test.all(:conditions => [ "tests.name ILIKE ?", "%#{@q}%" ], :order => [ :id.desc ], Test.application.record_type => @selectedRecordTypes) + Test.all(:conditions => [ "tests.description ILIKE ?", "%#{@q}%" ], :order => [ :id.desc ], Test.application.record_type => @selectedRecordTypes)

		# Get VRLO custom results
		@vrloResults = Array.new
		keysSearched = Array.new
		@selectedRecordTypes.each do |rtid|
			rt = RecordType.get(rtid)
			if(rt.isLinked)
				vrlo = VRLinkedObject.getByKey(rt.linkedObjectKey)
				if(!vrlo.nil? && !keysSearched.include?(vrlo.vrlo_key))
					vrloSearchResults = nil
					begin
						vrloSearchResults = vrlo.doSearch(@q)
					rescue Exception => e
						vrloSearchResults = nil
						Rollbar.error(e, "Error doing VRLO search", {:query => @q, :vrlo_key => rt.linkedObjectKey})
					end

					keysSearched << vrlo.vrlo_key
					require 'ipaddr'

					if(!vrloSearchResults.nil? && vrloSearchResults.size > 0)
						@vrloResults << {:title => vrlo.vrlo_name, :results => vrloSearchResults}
					end
				end
			end
		end

		erb :search_results
	end

	get '/confirmAlloc' do
		a = MonthlyAllocation.allocationForUser(session[:uid])
		a.update(:wasAutoSet => false)
		a.update(:wasMgrSet => false)
		redirect "/"
	end

	post '/clearSRCache' do
		halt 401 if(!canViewReview?(params[:aid]))
		srid = params[:srid]
		settings.redis.del("srdet_#{srid}")
		return 200
	end

	get '/help' do
		redirect "http://vulnreport.io/documentation"
	end
end