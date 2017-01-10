##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

class Vulnreport < Sinatra::Base
	post '/admin/settings/cache/evict/?' do
		key = params[:key]

		if(!settings.redis.get(key).nil?)
			settings.redis.del(key)
		end

		return 200
	end

	get '/admin/settings/cache/?' do 
		@hits = getSetting("cache_hits").to_i + settings.redis.get("cache_hits").to_i
		@misses = getSetting("cache_misses").to_i + settings.redis.get("cache_misses").to_i

		if(@hits == 0 && @misses == 0)
			@pct = 0
		else
			@pct = (@hits.to_f/(@hits.to_f+@misses.to_f))
		end

		keys = settings.redis.keys
		@keysTTL = Array.new
		keys.each do |k|
			@keysTTL << {:key => k, :ttl => settings.redis.ttl(k)}
		end

		erb :admin_vr_cache_settings
	end

	get '/admin/settings/mail/?' do
		@vr_mail_method = getSetting('VR_MAIL_METHOD')
		@vr_from_email = getSetting('VR_NOREPLY_EMAIL')

		if(@vr_mail_method == 'custom')
			@vr_mail_addr = getSetting('VR_MAIL_ADDR')
			@vr_mail_port = getSetting('VR_MAIL_PORT').to_i
			@vr_mail_domain = getSetting('VR_MAIL_DOMAIN')
			@vr_mail_user = getSetting('VR_MAIL_USER')
			@vr_mail_pass = getSetting('VR_MAIL_PASS')
		end

		erb :admin_vr_mail_settings
	end

	post '/admin/settings/mail/?' do
		vr_mail_method = params[:vr_mail_method].strip
		if(vr_mail_method != "sendmail" && vr_mail_method != "custom")
			vr_mail_method = "sendmail"
		end

		vr_from_email = params[:vr_from_email].strip

		setSetting('VR_MAIL_METHOD', vr_mail_method)
		setSetting('VR_NOREPLY_EMAIL', vr_from_email) unless (vr_from_email.nil? || vr_from_email.empty?)

		if(vr_mail_method == 'custom')
			vr_mail_addr = params[:vr_mail_addr].strip
			vr_mail_port = params[:vr_mail_port].to_i
			vr_mail_domain = params[:vr_mail_domain].strip
			vr_mail_user = params[:vr_mail_user].strip
			vr_mail_pass = params[:vr_mail_pass].strip

			setSetting('VR_MAIL_ADDR', vr_mail_addr) unless vr_mail_addr.nil?
			setSetting('VR_MAIL_PORT', vr_mail_port.to_s) unless vr_mail_port.nil?
			setSetting('VR_MAIL_DOMAIN', vr_mail_domain) unless vr_mail_domain.nil?
			setSetting('VR_MAIL_USER', vr_mail_user) unless vr_mail_user.nil?
			setSetting('VR_MAIL_PASS', vr_mail_pass) unless (vr_mail_pass.nil? || vr_mail_pass.empty?)

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
		else
			Pony.options = {
				:via => :sendmail
			}
		end

		redirect "/admin/settings/mail"
	end

	post '/admin/settings/crons/enable/?' do
		key = params[:key].to_s.strip
		crondata = settings.redis.get("vrcron_data_#{key.to_s}")
		
		return 404 if(crondata.nil?)
			
		crondata = JSON.parse(crondata, {:symbolize_names => true})
		crondata[:enabled] = true
		if(settings.redis.set("vrcron_data_#{key.to_s}", crondata.to_json))
			return 200
		else
			return 500
		end
	end

	post '/admin/settings/crons/disable/?' do
		key = params[:key].to_s.strip
		crondata = settings.redis.get("vrcron_data_#{key.to_s}")
		
		return 404 if(crondata.nil?)
			
		crondata = JSON.parse(crondata, {:symbolize_names => true})
		crondata[:enabled] = false
		if(settings.redis.set("vrcron_data_#{key.to_s}", crondata.to_json))
			return 200
		else
			return 500
		end
	end

	post '/admin/settings/crons/run/?' do
		key = params[:key].to_s.strip
		
		cron = nil
		VRCron.each do |c|
			if(key == c.to_s)
				cron = c
			end
		end
		
		return 404 if(cron.nil?)

		Thread.new do
			runVRCron(cron, true)
		end

		return 200
	end

	get '/admin/settings/crons/?' do
		@crons = Array.new

		VRCron.each do |cron|
			crondata = JSON.parse(settings.redis.get("vrcron_data_#{cron.to_s}"), {:symbolize_names => true})
			@crons << {:key => cron.to_s, :data => crondata}
		end

		erb :admin_vr_cron_settings
	end

	get '/admin/settings/?' do
		@vr_name = getSetting('VR_INS_NAME')
		@vr_root = getSetting('VR_ROOT')
		@vr_footer = getSetting('VR_FOOTER')
		@sshotMaxSize = getSetting('SSHOT_MAX_SIZE_KB')
		@payloadMaxSize = getSetting('PAYLOAD_MAX_SIZE_KB')
		@pdf_on = (getSetting('PDF_EXPORT_ON') == 'true')

		@sso_auth = (getSetting('AUTH_SSO_ENABLED') == 'true')
		@autoadd = (getSetting('AUTO_ADD_USERS') == 'true')
		@sso_name = getSetting('AUTH_SSO_NAME')
		@sso_issuer = getSetting('AUTH_SSO_ISSUER')
		@sso_target_url = getSetting('AUTH_SSO_TARGET_URL')
		@sso_cert_fingerprint = getSetting('AUTH_SSO_CERT_FINGERPRINT')

		@login_auth = (getSetting('AUTH_LOGIN_ENABLED') == 'true')
		@login_pwlen = getSetting('AUTH_LOGIN_PWLEN')

		@ip_restrictions = (getSetting('IP_RESTRICTIONS_ON') == 'true')
		@ip_restrictions_allowed = getSetting('IP_RESTRICTIONS_ALLOWED')
				
		@app_version = Vulnreport::VERSION::STRING
		@app_hostname = %x{hostname}

		erb :admin_vr_settings
	end

	post '/admin/settings/?' do
		vr_name = params[:vr_name].strip
		vr_root = params[:vr_root].strip
		vr_footer = params[:vr_footer].strip
		sshotMaxSize = params[:sshotMaxSize].strip.to_i
		payloadMaxSize = params[:payloadMaxSize].strip.to_i
		pdf_on = (!params[:pdf_on].nil?)

		sso_auth = (!params[:sso_auth].nil?)
		autoCreate = (!params[:autoCreate].nil?)
		sso_name = params[:sso_name].strip
		sso_issuer = params[:sso_issuer].strip
		sso_target_url = params[:sso_target_url].strip
		sso_cert_fingerprint = params[:sso_cert_fingerprint].strip

		login_auth = (!params[:login_auth].nil?)
		login_pwlen = params[:login_pwlen].strip

		ip_restrictions = (!params[:ip_restrictions].nil?)
		ip_restrictions_allowed = params[:ip_restrictions_allowed].strip
		if(!ip_restrictions_allowed.nil? && !ip_restrictions_allowed.empty?)
			ip_allowed_arr = ip_restrictions_allowed.split(",")
			ip_allowed_arr.map!{|s| s.strip}
		else
			#Don't allow IP restrictions to be turned on with nothing allowed
			ip_restrictions = false
		end

		if(!vr_name.nil? && !vr_name.empty?)
			setSetting('VR_INS_NAME', vr_name)
			settings.vrname = vr_name
		end

		setSetting('VR_ROOT', vr_root) unless (vr_root.nil? || vr_root.empty?)

		if(!vr_footer.nil? && !vr_footer.empty?)
			setSetting('VR_FOOTER', vr_footer)
			settings.vrfooter = vr_footer
		end

		if(sshotMaxSize <= 0 || sshotMaxSize > (1024*1024*12))
			sshotMaxSize = 2048
		end

		if(payloadMaxSize <= 0 || payloadMaxSize > (1024*1024*12))
			payloadMaxSize = 2048
		end

		setSetting('SSHOT_MAX_SIZE_KB', sshotMaxSize.to_s)
		setSetting('PAYLOAD_MAX_SIZE_KB', payloadMaxSize.to_s)
		setSetting('PDF_EXPORT_ON', pdf_on)

		setSetting('AUTH_SSO_ENABLED', sso_auth)
		setSetting('AUTO_ADD_USERS', autoCreate)
		setSetting('AUTH_SSO_NAME', sso_name)
		setSetting('AUTH_SSO_ISSUER', sso_issuer)
		setSetting('AUTH_SSO_TARGET_URL', sso_target_url)
		setSetting('AUTH_SSO_CERT_FINGERPRINT', sso_cert_fingerprint)

		setSetting('AUTH_LOGIN_ENABLED', login_auth)
		setSetting('AUTH_LOGIN_PWLEN', login_pwlen)

		setSetting('IP_RESTRICTIONS_ON', ip_restrictions)
		setSetting('IP_RESTRICTIONS_ALLOWED', ip_allowed_arr.join(',')) unless ip_allowed_arr.nil?

		redirect "/admin/settings"
	end

	get '/admin/users/new/?' do
		@orgs = Organization.all()
		@managerOptions = User.activeSorted()

		erb :admin_user_new
	end

	post '/admin/users/new/?' do
		newVerified = false
		if (!params[:isVerified].nil?)
			newVerified = true
		end
		newOrg = 0 if !newVerified

		newReportsOnly = false
		if(!params[:isReportsOnly].nil?)
			newReportsOnly = true
		end

		newAdmin = false
		if (!params[:isAdmin].nil? && !newReportsOnly)
			newAdmin = true
		end

		newName = params[:userName].strip
		newInits = params[:userInitials].strip
		newEmail = params[:userEmail].strip

		newOrg = params[:userOrg].to_i
		if(!newVerified)
			newOrg = 0
		end

		newGeo = params[:userGeo].to_i
		if(newGeo <= 0)
			newGeo = GEO::USA
		end

		newManager = params[:userMgr].to_i
		if(User.get(newManager).nil?)
			newManager = 0
		end

		newSSOUser = nil
		newSSOUser = nil
		newUsername = nil
		newPassword = nil

		sso_auth = (getSetting('AUTH_SSO_ENABLED') == 'true')
		login_auth = (getSetting('AUTH_LOGIN_ENABLED') == 'true')

		if(sso_auth)
			newSSOUser = params[:sso_user].strip
			newSSOUID = params[:sso_id].strip

			if(newSSOUser.nil? || newSSOUser == "" || newSSOUID.nil? || newSSOUID == "")
				@errstr = "SSO Information must be entered"
				return erb :error
			end
		end

		if(login_auth)
			newUsername = params[:login_user].strip
			newPassword = params[:login_password].strip
		end

		@user = User.create(:username => newUsername, :password => newPassword, :sso_user => newSSOUser, :sso_id => newSSOUID, :email => newEmail, :name => newName, :initials => newInits, :org => newOrg, :defaultGeo => newGeo, :manager_id => newManager, :admin => newAdmin, :reportsOnly => newReportsOnly)

		if(!@user.saved?)
			@errstr = "Error saving user"
			return erb :error
		end

		redirect "/admin/users/#{@user.id}"
	end

	get '/admin/users/:uid/?' do
		@user = User.get(params[:uid])
		if(@user.nil?)
			@errstr = "User not found"
			return erb :error 
		end
		
		@orgs = Organization.all()
		@logins = AuditRecord.all(:event_type => [EVENT_TYPE::USER_LOGIN, EVENT_TYPE::USER_LOGIN_FAILURE], :actor => @user.id, :order => [:event_at.desc], :limit => 10)
		@managerOptions = User.activeSorted()

		erb :admin_user_single
	end

	post '/admin/users/:uid/resetpw' do
		@user = User.get(params[:uid])
		if(@user.nil?)
			return 404
		end

		pwlen = getSetting("AUTH_LOGIN_PWLEN").to_i
		if(pwlen == 0)
			pwlen = 12
		end

		@newpass = SecureRandom.base64(pwlen)[0..(pwlen-1)]
		@user.password = @newpass
		if(@user.save)
			renderer = ERB.new(File.open("views/emails/passResetEmail.erb", "rb").read)
			body = renderer.result(binding)
			
			fromEmail = getSetting('VR_NOREPLY_EMAIL')
			Pony.mail(:to => @user.email, :from => fromEmail, :subject => "Vulnreport Password Reset", :html_body => body)

			return 200
		else
			Rollbar.error("Error saving user for password reset", {:uid => @user.id, :error => @user.errors.inspect})
			return 500
		end
	end

	post '/admin/users/:uid/?' do
		@user = User.get(params[:uid])
		if(@user.nil?)
			@errstr = "User not found"
			return erb :error 
		end

		newVerified = (!params[:isVerified].nil?)
		@user.org = 0 if !newVerified

		newActive = (!params[:isActive].nil?)
		@user.active = newActive

		newReportsOnly = (!params[:isReportsOnly].nil?)
		@user.reportsOnly = newReportsOnly

		newAllocationUser = (!params[:isAllocationUser].nil? && !newReportsOnly)
		@user.useAllocation = newAllocationUser

		newAllocCoeff = params[:allocCoeff].to_i
		newAllocCoeff = 12 if(newAllocCoeff <= 0)
		@user.allocCoeff = newAllocCoeff

		newAdmin = (!params[:isAdmin].nil? && !newReportsOnly)
		@user.admin = newAdmin

		newAuditor = (!params[:isAuditor].nil? && !newReportsOnly)
		@user.canAuditMonitors = newAuditor

		newConPasser = (!params[:isConPasser].nil? && !newReportsOnly)
		@user.canPassToCon = newConPasser

		newName = params[:userName].strip
		@user.name = newName unless newName.nil?

		newEmail = params[:email].strip
		@user.email = newEmail unless (newEmail.nil? || !isValidEmail?(newEmail))

		newInits = params[:userInitials].strip
		@user.initials = newInits unless newInits.nil?

		newExtEID = params[:user_ext_eid].strip
		@user.extEID = newExtEID unless newExtEID.nil?

		newOrg = params[:userOrg].to_i
		if(!newVerified)
			@user.org = 0
		else
			@user.org = newOrg unless newOrg == 0
		end

		newGeo = params[:userGeo].to_i
		@user.defaultGeo = newGeo unless newGeo == 0

		newManager = params[:userMgr].to_i
		if(User.get(newManager).nil?)
			newManager = 0
		end
		@user.manager_id = newManager

		newRequireApproval = (!params[:isApprovalRequired].nil?)
		@user.requireApproval = newRequireApproval

		if(newRequireApproval)
			newApproverUsers = Array.new
			if(!params[:approver_users].nil?)
				params[:approver_users].each do |uid|
					newApproverUsers << uid.to_i
				end
			end

			#If no approvers selected automatically add manager, if one exists
			if(newApproverUsers.size == 0 && !newManager.nil? && newManager > 0)
				newApproverUsers << newManager
			end

			newApproverUsers = nil if(newApproverUsers.size == 0)
			@user.approver_users = newApproverUsers

			newApproverOrgs = Array.new
			if(!params[:approver_orgs].nil?)
				params[:approver_orgs].each do |oid|
					newApproverOrgs << oid.to_i
				end
			end
			newApproverOrgs = nil if(newApproverOrgs.size == 0)
			@user.approver_orgs = newApproverOrgs
		else
			@user.approver_users = nil
			@user.approver_orgs = nil
		end

		if(getSetting('AUTH_SSO_ENABLED') == 'true')
			newSSOUser = params[:sso_user].strip
			@user.sso_user = newSSOUser unless newSSOUser.nil?

			newSSOId = params[:sso_id].strip
			@user.sso_id = newSSOId unless newSSOId.nil?
		end

		if(getSetting('AUTH_LOGIN_ENABLED') == 'true')
			newUsername = params[:login_user]
			@user.username = newUsername unless newUsername.nil?
		end

		@user.save

		redirect "/admin/users/#{@user.id}"
	end

	get '/admin/users/:uid/loginhistory/?' do
		@user = User.get(params[:uid])
		if(@user.nil?)
			@errstr = "User not found"
			return erb :error 
		end

		#Offset parse
		lim = 50

		if(params[:os].nil?)
			offset = 0
		else
			offset = params[:os].to_i
		end
		@total = AuditRecord.count(:event_type => [EVENT_TYPE::USER_LOGIN, EVENT_TYPE::USER_LOGIN_FAILURE], :actor => @user.id)

		@start = offset+1
		@end = (offset+lim > @total) ? @total : (offset+lim)

		@next = nil
		if(offset+lim < @total)
			@next = offset+lim
		end

		@last = nil
		if(offset > 0)
			@last = offset-lim
			if(@last < 0)
				@last = 0
			end
		end		
		
		@logins = AuditRecord.all(:event_type => [EVENT_TYPE::USER_LOGIN, EVENT_TYPE::USER_LOGIN_FAILURE], :actor => @user.id, :order => [:event_at.desc], :limit => lim, :offset => offset)

		erb :admin_user_single_loginhistory
	end

	get '/admin/users/?' do
		@adminUsers = Array.new
		@conUsers = Array.new
		@activeUsers = Array.new
		@roUsers = Array.new
		@unverified = Array.new
		@inactive = Array.new

		User.all().each do |u|
			org = Organization.get(u.org) unless u.org == 0

			status = "Active"
			if(!u.active)
				status = "Inactive"
			elsif(u.admin && u.org != 0)
				status = "Admin"
			elsif(u.reportsOnly && u.org != 0)
				status = "Reports Only"
			elsif(u.org == 0)
				status = "Unverified"
			end

			lastLogin = u.lastLogin
			lastLoginStr = ""

			if(!lastLogin.nil?)
				lastLoginStr = lastLogin.event_at.strftime('%-d %b %Y - %H:%M')
			end

			if(u.org == 0)
				thisUserHash = {:uid => u.id, :name => u.name, :inits => u.initials, :status => status, :org => "", :oid => 0, :mgr => u.manager, :email => u.email, :lastLogin => lastLoginStr}
			else
				thisUserHash = {:uid => u.id, :name => u.name, :inits => u.initials, :status => status, :org => org.name, :oid => org.id, :mgr => u.manager, :email => u.email, :lastLogin => lastLoginStr}
			end

			if(!u.active)
				@inactive << thisUserHash
			else
				if(u.admin && u.org != 0)
					@adminUsers << thisUserHash
				end

				if(u.org != 0)
					if(org.contractor)
						@conUsers << thisUserHash
					elsif(u.reportsOnly)
						@roUsers << thisUserHash
					else
						@activeUsers << thisUserHash
					end
				else
					@unverified << thisUserHash
				end
			end
		end

		@adminUsers.sort!{|x,y| x[:name].split(" ").last <=> y[:name].split(" ").last }
		@conUsers.sort!{|x,y| x[:name].split(" ").last <=> y[:name].split(" ").last }
		@activeUsers.sort!{|x,y| x[:name].split(" ").last <=> y[:name].split(" ").last }
		@roUsers.sort!{|x,y| x[:name].split(" ").last <=> y[:name].split(" ").last }
		@inactive.sort!{|x,y| x[:name].split(" ").last <=> y[:name].split(" ").last }

		erb :admin_users
	end

	get '/admin/orgs/new/?' do
		erb :admin_org_new
	end

	post '/admin/orgs/new/?' do
		newSuper = false
		if (!params[:isSuper].nil?)
			newSuper = true
		end

		newContractor = false
		if (!params[:isCon].nil?)
			newContractor = true
			newSuper = false
		end

		newName = params[:orgName].strip

		org = Organization.create(:name => newName, :super => newSuper, :contractor => newContractor)
		org.save

		redirect "/admin/orgs/"
	end

	get '/admin/orgs/:oid/?' do
		@org = Organization.get(params[:oid])
		@orgs = Organization.all()

		if(@org.nil?)
			@errstr = "Org not found"
			return erb :error 
		end

		@users = Array.new
		User.all(:org => @org.id).each do |u|
			status = "Active"
			if(!u.active)
				status = "Inactive"
			elsif(u.admin && u.org != 0)
				status = "Admin"
			elsif(u.reportsOnly && u.org != 0)
				status = "Reports Only"
			elsif(u.org == 0)
				status = "Unverified"
			end

			lastLogin = u.lastLogin
			lastLoginStr = ""

			if(!lastLogin.nil?)
				lastLoginStr = lastLogin.event_at.strftime('%-d %b %Y - %H:%M')
			end

			@users << {:uid => u.id, :name => u.name, :inits => u.initials, :status => status, :mgr => u.manager, :email => u.email, :lastLogin => lastLoginStr}
		end

		@appRecordTypes = RecordType.allAppRecordTypes()
		@allowedRTs = getAllowedRTsForOrg(@org.id)

		@dashConfigs = DashConfig.all(:active => true)

		erb :admin_org_single
	end

	post '/admin/orgs/:oid/?' do
		@org = Organization.get(params[:oid])
		if(@org.nil?)
			@errstr = "Org not found"
			return erb :error 
		end

		newSuper = false
		if (!params[:isSuper].nil?)
			newSuper = true
		end

		newCanReport = false
		if (!params[:canReport].nil?)
			newCanReport = true
		end

		newContractor = false
		if (!params[:isCon].nil?)
			newContractor = true
			newSuper = false
		end

		newRequireApproval = (!params[:isApprovalRequired].nil?)
		@org.requireApproval = newRequireApproval

		if(newRequireApproval)
			newApproverUsers = Array.new
			if(!params[:approver_users].nil?)
				params[:approver_users].each do |uid|
					newApproverUsers << uid.to_i
				end
			end
			newApproverUsers = nil if(newApproverUsers.size == 0)
			@org.approver_users = newApproverUsers

			newApproverOrgs = Array.new
			if(!params[:approver_orgs].nil?)
				params[:approver_orgs].each do |oid|
					newApproverOrgs << oid.to_i
				end
			end
			newApproverOrgs = nil if(newApproverOrgs.size == 0)
			@org.approver_orgs = newApproverOrgs
		else
			@org.approver_users = nil
			@org.approver_orgs = nil
		end

		@org.super = newSuper
		@org.canReport = newCanReport
		@org.contractor = newContractor

		newName = params[:orgName].strip
		@org.name = newName unless newName.nil?

		if(params[:dashConfig].to_i != @org.dashconfig)
			#Set all org users to the new choice
			User.all(:org => @org.id).update(:dashOverride => -1)
		end
		@org.dashconfig = params[:dashConfig].to_i

		@org.save

		allowedRTs = Array.new
		if(!params[:rtms].nil?)
			params[:rtms].each do |rtid|
				allowedRTs << rtid.to_i
			end
		end

		allowedRTs.each do |rtid|
			if(!orgAllowedRT?(@org.id, rtid))
				allowRTForOrg(@org.id, rtid)
			end
		end

		RecordType.allAppRecordTypes().each do |rt|
			if(!allowedRTs.include?(rt.id) && orgAllowedRT?(@org.id, rt.id))
				removeRTForOrg(@org.id, rt.id)
			end
		end

		redirect "/admin/orgs/#{@org.id}"
	end

	get '/admin/orgs/:oid/delete/?' do
		@org = Organization.get(params[:oid])
		if(@org.nil?)
			@errstr = "Org not found"
			return erb :error 
		end

		@orgOptions = Organization.all(:id.not => @org.id)
		@users = User.all(:org => @org.id)

		erb :admin_org_delete_conf
	end

	post '/admin/orgs/:oid/delete/?' do
		@org = Organization.get(params[:oid])
		if(@org.nil?)
			@errstr = "Org not found"
			return erb :error 
		end

		confirm = false
		if(params[:confirm].downcase == "confirm")
			confirm = true
		end

		if(!confirm)
			redirect "/admin/orgs/#{@org.id}"
			return
		else
			newOrgId = params[:newOrg].to_i
			if(newOrgId == @org.id)
				@errstr = "Invalid migration org"
				return erb :error
			end

			newOrg = Organization.get(newOrgId)
			if(newOrg.nil?)
				@errstr = "Invalid migration org"
				return erb :error
			end

			#Move Users
			User.all(:org => @org.id).each do |u|
				u.org = newOrgId
				if(!u.save)
					@errstr = "Problem moving user - #{u.errors.inspect}"
					return erb :error
				end
			end

			#Move over apps and tests
			Test.all(:org_created => @org.id).each do |t|
				t.org_created = newOrgId
				if(!t.save)
					@errstr = "Problem moving test - #{t.errors.inspect}"
					return erb :error
				end
			end

			Application.all(:org_created => @org.id).each do |a|
				a.org_created = newOrgId
				if(!a.save)
					@errstr = "Problem moving test - #{a.errors.inspect}"
					return erb :error
				end
			end

			#Delete perm links for RTs
			Link.all(:fromType => LINK_TYPE::ORGANIZATION, :fromId => @org.id, :toType => LINK_TYPE::ALLOW_APP_RT).destroy

			#Delete the org
			@org.destroy

			redirect "/admin/orgs/#{newOrgId}"
			return 
		end
	end

	get '/admin/orgs/?' do
		@superOrgs = Array.new
		@regOrgs = Array.new
		@conOrgs = Array.new

		Organization.all().each do |o|
			if(o.super)
				@superOrgs << {:id => o.id, :name => o.name, :num => User.count(:org => o.id)}
				if(!o.contractor)
					@regOrgs << {:id => o.id, :name => o.name, :num => User.count(:org => o.id)}
				end
			else
				if(o.contractor)
					@conOrgs << {:id => o.id, :name => o.name, :num => User.count(:org => o.id)}
				else
					@regOrgs << {:id => o.id, :name => o.name, :num => User.count(:org => o.id)}
				end
			end
		end

		erb :admin_orgs
	end

	get '/admin/vulntypes/new/?' do
		@appRecordTypes = RecordType.appRecordTypes()
		@vsOptions = VulnSource.all(:enabled => true)
		@flagOptions = Flag.all()

		erb :admin_vt_new
	end

	post '/admin/vulntypes/new/?' do
		newEnabled = false
		if (!params[:isEnabled].nil?)
			newEnabled = true
		end

		newName = params[:vtName].strip
		newLabel = params[:vtLabel].strip
		newCwe = params[:cwe].strip.to_i
		if(newCwe <= 0)
			newCwe = nil
		end
		newPri = params[:vtPri].to_i
		newDefaultSource = params[:vtDefaultSource].to_i
		newHtml = params[:html].strip
		
		newRts = Array.new
		if(!params[:rtms].nil?)
			params[:rtms].each do |rtid|
				newRts << rtid.to_i
			end
		end

		newSecs = Array.new
		if(!params[:secms].nil?)
			params[:secms].each do |sid|
				newSecs << sid.to_i
			end
		end

		newFlags = Array.new
		if(!params[:flagms].nil?)
			params[:flagms].each do |fid|
				newFlags << fid.to_i
			end
		end

		vt = VulnType.create(:name => newName, :label => newLabel, :cwe_mapping => newCwe, :priority => newPri, :html => newHtml, :enabled => newEnabled, :enabledRTs => newRts, :enabledSections => newSecs, :requiredFlags => newFlags, :defaultSource => newDefaultSource)
		
		redirect "/admin/vulntypes/"
	end

	get '/admin/vulntypes/export/?' do
		vulnTypes = VulnType.all()

		builder = Nokogiri::XML::Builder.new do |xml|
			xml.vulntypes{
				vulnTypes.each do |vt|
					xml.vulntype{
						xml.name vt.name
						xml.label vt.label
						xml.cwe vt.cwe_mapping
						xml.html vt.html
						xml.priority vt.priority
						xml.enabledSections vt.enabledSections
					}
				end
			}
		end

		attachment "vulntypes.xml"
		return builder.to_xml
	end

	get '/admin/vulntypes/import/?' do
		erb :admin_vt_import
	end

	post '/admin/vulntypes/import/?' do
		data = params[:vt_import]
		
		filesize = (File.size(data[:tempfile]).to_f)/1024
		if(filesize > 1024)
			@errstr = "XML File too large - Max 1MB"
			return erb :error
		end

		file = File.open(data[:tempfile], "rb")
		doc = Nokogiri::XML(file)

		@vts = Array.new
		doc.xpath("//vulntype").each do |vt|
			vtname = vt.at_xpath(".//name").children.first.text.to_s

			vtlabel = vt.at_xpath(".//label").children
			if(!vtlabel.nil? && vtlabel.size > 0)
				vtlabel = vtlabel.first.text.to_s
			else
				vtlabel = nil
			end

			vtcwe = vt.at_xpath(".//cwe").children
			if(!vtcwe.nil? && vtcwe.size > 0)
				vtcwe = vtcwe.first.text.to_i
			else
				vtcwe = nil
			end			
			
			vtpriority = vt.at_xpath(".//priority").children
			if(!vtpriority.nil? && vtpriority.size > 0)
				vtpriority = vtpriority.first.text.to_i
			else
				vtpriority = nil
			end

			vtenabled = vt.at_xpath(".//enabledSections").children.first.text.gsub("[","").gsub("]","").split(",").map{|s| s.to_i}

			vthtml = vt.at_xpath(".//html").children
			if(!vthtml.nil? && vthtml.size > 0)
				vthtml = vthtml.first.text.to_s
			else
				vthtml = nil
			end

			newvt = {:name => vtname, :label =>vtlabel, :cwe => vtcwe, :priority => vtpriority, :enabled => vtenabled, :html => vthtml}
			@vts << newvt
		end

		@appRecordTypes = RecordType.appRecordTypes()

		erb :admin_vt_import_confirm
	end

	post '/admin/vulntypes/doImport/?' do
		selected = params[:vt_confirms].map{|e| e.to_i}

		newRts = Array.new
		if(!params[:rtms].nil?)
			params[:rtms].each do |rtid|
				newRts << rtid.to_i
			end
		end

		selected.each do |idx|
			vtname = params["vt_name_#{idx}"].to_s
			
			vtlabel = params["vt_label_#{idx}"]
			if(vtlabel.nil? || vtlabel.to_s.strip.empty?)
				vtlabel = nil
			else
				vtlabel = vtlabel.to_s
			end

			vtcwe = params["vt_cwe_#{idx}"]
			if(vtcwe.nil? || vtcwe.to_s.strip.empty?)
				vtcwe = nil
			else
				vtcwe = vtcwe.to_i
			end

			vtpriority = params["vt_priority_#{idx}"]
			if(vtpriority.nil? || vtpriority.to_s.strip.empty?)
				vtpriority = nil
			else
				vtpriority = vtpriority.to_i
			end

			vtenabled = params["vt_enabled_#{idx}"]
			if(vtenabled.nil? || vtenabled.to_s.strip.empty?)
				vtenabled = []
			else
				vtenabled = vtenabled.to_s.gsub("[","").gsub("]","").split(",").map{|s| s.to_i}
			end

			vthtml = params["vt_html_#{idx}"]
			if(vthtml.nil? || vthtml.to_s.strip.empty?)
				vthtml = nil
			else
				vthtml = vthtml.to_s
			end

			vt = VulnType.create(:name => vtname, :label => vtlabel, :cwe_mapping => vtcwe, :priority => vtpriority, :html => vthtml, :enabled => true, :enabledRTs => newRts, :enabledSections => vtenabled)
		end

		redirect "/admin/vulntypes/"
	end

	get '/admin/vulntypes/:vtid/?' do
		@vt = VulnType.get(params[:vtid])
		if(@vt.nil?)
			@errstr = "Type not found"
			return erb :error 
		end

		@enabled = ""
		if(@vt.enabled)
			@enabled = "checked"
		end

		@appRecordTypes = RecordType.appRecordTypes()
		@vsOptions = VulnSource.all(:enabled => true)
		@flagOptions = Flag.all()

		erb :admin_vt_single
	end

	post '/admin/vulntypes/:vtid/?' do
		@vt = VulnType.get(params[:vtid])
		if(@vt.nil?)
			@errstr = "Type not found"
			return erb :error 
		end

		newEnabled = false
		if (!params[:isEnabled].nil?)
			newEnabled = true
		end

		@vt.enabled = newEnabled

		newName = params[:vtName].strip
		@vt.name = newName unless newName.nil?

		newLabel = params[:vtLabel].strip
		@vt.label = newLabel unless newLabel.nil?

		newCwe = params[:cwe].strip.to_i
		if(newCwe <= 0)
			@vt.cwe_mapping = nil
		else
			@vt.cwe_mapping = newCwe
		end

		newPriority = params[:vtPri]
		if(newPriority.nil? || newPriority.to_i < 0)
			newPriority = nil
		else
			newPriority = newPriority.to_i
		end
		@vt.priority = newPriority

		newDefaultSource = params[:vtDefaultSource].to_i
		@vt.defaultSource = newDefaultSource

		newHtml = params[:html].strip
		@vt.html = newHtml unless newHtml.nil?

		newRts = Array.new
		if(!params[:rtms].nil?)
			params[:rtms].each do |rtid|
				newRts << rtid.to_i
			end
		end

		@vt.enabledRTs = newRts

		newSecs = Array.new
		if(!params[:secms].nil?)
			params[:secms].each do |sid|
				newSecs << sid.to_i
			end
		end

		@vt.enabledSections = newSecs

		newFlags = Array.new
		if(!params[:flagms].nil?)
			params[:flagms].each do |fid|
				newFlags << fid.to_i
			end
		end

		@vt.requiredFlags = newFlags

		@vt.save

		@enabled = ""
		if(@vt.enabled)
			@enabled = "checked"
		end

		redirect "/admin/vulntypes/#{@vt.id}"
	end

	get '/admin/vulntypes/?' do
		@vulnTypes = VulnType.all()

		erb :admin_vts
	end

	get '/admin/vtids/?' do
		@vts = VulnType.all(:enabled => true, :order => [:id.asc])
		erb :admin_vtids
	end

	get '/admin/customVTs/?' do
		@customVTs = Array.new
		@counts = Array.new
		@firstUseVID = Array.new #First VID of use to look up later
		@usedTIDs = Array.new #array of arrays, uses of each
		downcased = Array.new

		Vulnerability.all(:vulntype => 0).each do |vt|
			if(!downcased.include?(vt.custom.downcase))
				@customVTs << vt.custom
				downcased = @customVTs.map(&:downcase)
				@counts << 1
				@firstUseVID << vt.id
				use = Array.new
				use << vt.test.id.to_s + "|" + vt.test.name + "|" + vt.test.application.name
				@usedTIDs << use
			else
				idx = downcased.index(vt.custom.downcase)
				@counts[idx] += 1
				@usedTIDs[idx] << vt.test.id.to_s + "|" + vt.test.name + "|" + vt.test.application.name
			end
		end

		erb :admin_vts_custom
	end

	post '/admin/customVTs/newFromCVT/?' do
		vid = params[:fuVID].to_i
		v = Vulnerability.get(vid)

		if(v.vulntype != 0)
			@errstr = "Not a valid custom vuln ID"
			erb :error
		end

		@vtName = v.custom
		@appRecordTypes = RecordType.appRecordTypes()
		@vsOptions = VulnSource.all(:enabled => true)
		@flagOptions = Flag.all()

		erb :admin_vt_new_from_cvt
	end

	post '/admin/customVTs/doNewFromCVT/?' do
		origCVText = params[:cvt_txt]

		#Create VT
		newEnabled = false
		if (!params[:isEnabled].nil?)
			newEnabled = true
		end

		newName = params[:vtName].strip
		newDefaultSource = params[:vtDefaultSource].to_i
		newHtml = params[:html].strip
		newLabel = params[:vtLabel].strip
		newCwe = params[:cwe].strip.to_i
		if(newCwe <= 0)
			newCwe = nil
		end
		newPri = params[:vtPri].to_i

		newRts = Array.new
		if(!params[:rtms].nil?)
			params[:rtms].each do |rtid|
				newRts << rtid.to_i
			end
		end

		newSecs = Array.new
		if(!params[:secms].nil?)
			params[:secms].each do |sid|
				newSecs << sid.to_i
			end
		end

		newFlags = Array.new
		if(!params[:flagms].nil?)
			params[:flagms].each do |fid|
				newFlags << fid.to_i
			end
		end

		vt = VulnType.create(:name => newName, :label => newLabel, :cwe_mapping => newCwe, :priority => newPri, :html => newHtml, :enabled => newEnabled, :enabledRTs => newRts, :enabledSections => newSecs, :requiredFlags => newFlags, :defaultSource => newDefaultSource)
		vt.save

		Vulnerability.all(:vulntype => 0, :custom => origCVText).each do |v|
			v.vulntype = vt.id
			v.custom = nil
			v.save
		end

		redirect "/admin/vulntypes/"
	end

	post '/admin/customVTs/mergeFromCVT/?' do
		@vts = VulnType.all(:enabled => true)

		vid = params[:fuVID].to_i
		v = Vulnerability.get(vid)

		if(v.vulntype != 0)
			@errstr = "Not a valid custom vuln ID"
			erb :error
		end

		@vtName = v.custom

		erb :admin_vt_merge_cvt
	end

	post '/admin/customVTs/doMergeFromCVT/?' do
		origCVText = params[:cvt_txt]
		mergeID = params[:svt].to_i

		mergeVT = VulnType.get(mergeID)

		if(mergeVT.nil?)
			@errstr = "Not a valid VTID"
			erb :error
		end

		Vulnerability.all(:vulntype => 0, :custom => origCVText).each do |v|
			v.vulntype = mergeVT.id
			v.custom = nil
			v.save
		end

		redirect "/admin/vulntypes/"
	end

	get '/admin/recordTypes/?' do
		@appRecordTypes = RecordType.all(:object => LINK_TYPE::APPLICATION)

		erb :admin_rts
	end

	get '/admin/recordTypes/new/?' do
		@linkOptions = Array.new
		VRLinkedObject.each do |vrlo|
			@linkOptions << {:name => vrlo.vrlo_name.to_s, :key => vrlo.vrlo_key.to_s}
		end
		
		erb :admin_rt_new
	end

	post '/admin/recordTypes/new/?' do
		name = params[:rtName].strip.to_s
		desc = params[:rtDesc].strip.to_s
		obj = LINK_TYPE::APPLICATION
		linkObj = params[:rtLinkTo]
		
		active = (!params[:isActive].nil?)
		link = (!params[:isLinked].nil? && linkObj != "0")

		if(name.nil? || name.empty?)
			@errstr = "Record Type must have a name"
			return erb :error
		end

		if(link)
			rt = RecordType.create(:object => obj, :name => name, :description => desc, :isLinked => true, :linkedObjectKey => linkObj)
		else
			rt = RecordType.create(:object => obj, :name => name, :description => desc, :isLinked => false)
		end

		VulnType.all().each do |vt|
			curTypes = vt.enabledRTs
			if(curTypes.nil?)
				curTypes = Array.new
			end
			curTypes << rt.id
			vt.enabledRTs = curTypes
			vt.save
		end

		redirect "/admin/recordTypes/#{rt.id}"
	end

	get '/admin/recordTypes/:rtid/?' do
		rtid = params[:rtid].to_i

		@rt = RecordType.get(rtid)
		if(@rt.nil?)
			@errstr = "Unable to find RecordType"
			return erb :error
		end

		@exportFormats = ExportFormat.all()

		@regOrgs = Organization.all(:contractor => false)
		@conOrgs = Organization.all(:contractor => true)
		@orgsAllowed = getOrgsAllowedForRT(@rt.id)
		@linkOptions = Array.new
		VRLinkedObject.each do |vrlo|
			@linkOptions << {:name => vrlo.vrlo_name.to_s, :key => vrlo.vrlo_key.to_s}
		end
		
		@vulnTypes = VulnType.all(:enabled => true).sort{ |x,y| x.name <=> y.name}
		@enabledVTs = Array.new
		VulnType.getByRecordType(rtid).each do |vt|
			@enabledVTs << vt.id
		end

		erb :admin_rt_single
	end

	post '/admin/recordTypes/:rtid/?' do
		rtid = params[:rtid].to_i

		rt = RecordType.get(rtid)
		if(rt.nil?)
			@errstr = "Unable to find RecordType"
			return erb :error
		end

		name = params[:rtName].strip.to_s
		desc = params[:rtDesc].strip.to_s
		linkObj = params[:rtLinkTo]
		exportFormat = params[:rtExport].to_i
		newPrisStr = params[:rtPriorities].strip.to_s
		
		active = (!params[:isActive].nil?)
		link = (!params[:isLinked].nil? && linkObj != "0")
		isPassable = (!params[:isPassable].nil?)
		isProvPassable = (!params[:isProvPassable].nil?)
		defaultPrivate = (!params[:defaultPrivate].nil?)
		
		rt.active = active
		rt.name = name
		rt.description = desc
		rt.isLinked = link
		rt.linkedObjectKey = linkObj
		rt.canBePassedToCon = isPassable
		rt.canBeProvPassed = isProvPassable
		rt.defaultPrivate = defaultPrivate
		rt.exportFormat = exportFormat

		rt.save

		newPris = newPrisStr.split(',')
		newPris.each_with_index do |str, idx|
			next if(str.nil? || str.length > 50)
			rt.setVulnPriorityString(idx, str)
		end

		allowedOrgs = Array.new
		if(!params[:orgms].nil?)
			params[:orgms].each do |oid|
				allowedOrgs << oid.to_i
			end
		end

		allowedOrgs.each do |oid|
			if(!orgAllowedRT?(oid, rt.id))
				allowRTForOrg(oid, rt.id)
			end
		end

		Organization.all.each do |org|
			if(!allowedOrgs.include?(org.id) && orgAllowedRT?(org.id, rt.id))
				removeRTForOrg(org.id, rt.id)
			end
		end

		enabledVTs = Array.new
		if(!params[:vtms].nil?)
			params[:vtms].each do |vtid|
				enabledVTs << vtid.to_i
			end
		end

		VulnType.all().each do |vt|
			vtEnabled = vt.enabledRTs
			if(!vtEnabled.nil? && vtEnabled.include?(rt.id) && !enabledVTs.include?(vt.id))
				vtEnabled.delete(rt.id)
			end

			if(!vtEnabled.nil? && !vtEnabled.include?(rt.id) && enabledVTs.include?(vt.id))
				vtEnabled << rt.id
			end

			vt.enabledRTs = vtEnabled
			vt.save
		end

		redirect "/admin/recordTypes/#{rt.id}" 
	end

	get '/admin/exportFormats/?' do
		@exportFormats = ExportFormat.all()

		erb :admin_efs
	end

	get '/admin/exportFormats/new/?' do
		erb :admin_ef_new
	end

	post '/admin/exportFormats/new/?' do
		name = params[:efName].strip.to_s
		desc = params[:efDesc].strip.to_s
		
		if(name.nil? || name.empty?)
			@errstr = "Record Type must have a name"
			return erb :error
		end

		defaultFile = File.open("exportTemplates/default.erb", "rb")
		defaultContents = defaultFile.read

		ef = ExportFormat.create(:name => name, :description => desc, :erb => defaultContents)
		redirect "/admin/exportFormats/#{ef.id}"
	end

	get '/admin/exportFormats/:efid/?' do
		efid = params[:efid].to_i

		if(efid != 0)
			@ef = ExportFormat.get(efid)
			if(@ef.nil?)
				@errstr = "Unable to find ExportFormat"
				return erb :error
			end
			@default = false
		else
			@default = true
		end

		if(efid == 0)
			f = File.open("exportTemplates/default.erb", "rb")
			@efERB = f.read
		else
			@efERB = @ef.erb
		end

		erb :admin_ef_single
	end

	post '/admin/exportFormats/:efid/?' do
		efid = params[:efid].to_i

		if(efid != 0)
			ef = ExportFormat.get(efid)
			if(ef.nil?)
				@errstr = "Unable to find ExportFormat"
				return erb :error
			end
			default = false

			name = params[:efName].strip.to_s
			desc = params[:efDesc].strip.to_s
			
			ef.name = name
			ef.description = desc
			
			ef.save
		else
			default = true
		end

		newFileContents = params[:efTemplateCode].strip.to_s

		if(efid == 0)
			File.open("exportTemplates/default.erb", "w"){ |f| f.write(newFileContents) }
		else
			ef.erb = newFileContents
			ef.save
		end

		redirect "/admin/exportFormats/#{efid}"
	end

	get '/admin/dashConfigs/?' do
		@dashConfigs = DashConfig.all()

		erb :admin_dcs
	end

	get '/admin/dashConfigs/new/?' do
		erb :admin_dc_new
	end

	post '/admin/dashConfigs/new/?' do
		name = params[:name].strip.to_s
		desc = params[:desc].strip.to_s
		
		if(name.nil? || name.empty?)
			@errstr = "Dashboard Config must have a name"
			return erb :error
		end

		dc = DashConfig.create(:name => name, :description => desc, :panels => Array.new, :stats => Array.new)
		redirect "/admin/dashConfigs/#{dc.id}"
	end

	get '/admin/dashConfigs/:dcid/?' do
		dcid = params[:dcid].to_i

		@dc = DashConfig.get(dcid)
		if(@dc.nil?)
			@errstr = "Unable to find DashConfig"
			return erb :error
		end

		if(@dc.customCode)
			erb :admin_dc_single_cc
		else
			@rtOpts = RecordType.appRecordTypes()
			@nonRtTypes = NON_RT_DASHPANELS

			erb :admin_dc_single
		end
	end

	post '/admin/dashConfigs/:dcid/newPanel/?' do
		dcid = params[:dcid].to_i

		dc = DashConfig.get(dcid)
		if(dc.nil?)
			@errstr = "Unable to find DashConfig"
			return erb :error
		end

		newPanelTitle = params[:panelTitle].strip.to_s
		newPanelColor = params[:panelColor].strip.to_s
		newPanelType = params[:panelType].to_i
		newPanelRecordType = params[:panelRecordType].to_i
		newPanelMaxWks = params[:panelMaxWks].to_i
		newPanelMaxWks = 0 if(newPanelMaxWks < 0)
		newPanelZeroText = params[:panelZeroText].strip.to_s
		if(newPanelZeroText.nil? || newPanelZeroText.empty?)
			newPanelZeroText = "No Records Returned"
		end

		newPanelHash = {:title => newPanelTitle, :color => newPanelColor, :type => newPanelType, :rt => newPanelRecordType, :maxwks => newPanelMaxWks, :zerotext => newPanelZeroText}
		dc.addPanel(newPanelHash)

		redirect "/admin/dashConfigs/#{dc.id}"
	end

	post '/admin/dashConfigs/:dcid/editPanel/:pidx/?' do
		dcid = params[:dcid].to_i
		pidx = params[:pidx].to_i

		dc = DashConfig.get(dcid)
		if(dc.nil?)
			@errstr = "Unable to find DashConfig"
			return erb :error
		end

		panel = dc.panels[pidx.to_i]
		if(panel.nil?)
			@errstr = "Unable to find Panel index #{pidx} on DC ID #{dcid}"
			return erb :error
		end

		if(params[:save].downcase == "delete")
			dc.panels.delete_at(pidx)
			
			dc.make_dirty(:panels)
			dc.save
		else
			newPanelTitle = params[:panelTitle].strip.to_s
			newPanelColor = params[:panelColor].strip.to_s
			newPanelType = params[:panelType].to_i
			newPanelRecordType = params[:panelRecordType].to_i
			newPanelMaxWks = params[:panelMaxWks].to_i
			newPanelMaxWks = 0 if(newPanelMaxWks < 0)
			newPanelZeroText = params[:panelZeroText].strip.to_s

			panel[:title] = newPanelTitle
			panel[:color] = newPanelColor
			panel[:type] = newPanelType
			panel[:rt] = newPanelRecordType
			panel[:maxwks] = newPanelMaxWks
			panel[:zerotext] = newPanelZeroText

			dc.make_dirty(:panels)
			dc.save
		end

		redirect "/admin/dashConfigs/#{dc.id}"
	end

	get '/admin/dashConfigs/:dcid/delete/?' do
		dcid = params[:dcid].to_i

		@dc = DashConfig.get(dcid)
		if(@dc.nil?)
			@errstr = "Unable to find DashConfig"
			return erb :error
		end

		@dcOptions = DashConfig.all(:id.not => @dc.id)
		@orgs = Organization.all(:dashconfig => @dc.id)
		@users = User.all(:dashOverride => @dc.id)

		erb :admin_dc_delete_conf
	end

	post '/admin/dashConfigs/:dcid/delete/?' do
		dcid = params[:dcid].to_i

		@dc = DashConfig.get(dcid)
		if(@dc.nil?)
			@errstr = "Unable to find DashConfig"
			return erb :error
		end

		confirm = false
		if(params[:confirm].downcase == "confirm")
			confirm = true
		end

		if(!confirm)
			redirect "/admin/dashConfigs/#{@dc.id}"
			return
		else
			newDcId = params[:newDc].to_i
			if(newDcId == @dc.id)
				@errstr = "Invalid migration Dash Config"
				return erb :error
			end

			newDc = DashConfig.get(newDcId)
			if(newDc.nil? && newDcId != 0)
				@errstr = "Invalid migration Dash Config"
				return erb :error
			end

			#Reset Users to no override
			User.all(:dashOverride => @dc.id).update(:dashOverride => -1)

			#Move over orgs
			Organization.all(:dashconfig => @dc.id).update(:dashconfig => newDcId)

			#Delete the DC
			@dc.destroy

			redirect "/admin/dashConfigs"
		end
	end

	post '/admin/dashConfigs/:dcid/?' do
		dcid = params[:dcid].to_i

		dc = DashConfig.get(dcid)
		if(dc.nil?)
			@errstr = "Unable to find DashConfig"
			return erb :error
		end

		newName = params[:name].strip.to_s
		newDesc = params[:desc].strip.to_s
		
		dc.active = (!params[:isActive].nil?)
		dc.name = newName
		dc.description = newDesc

		if(!dc.customCode)
			dc.showStats = (!params[:showStats].nil?)

			newStatBlocks = Array.new
			(1..4).each do |i|
				type = params["block#{i}_type"].to_i
				rt = params["block#{i}_rt"].to_i
				text = params["block#{i}_text"].to_s
				if(text.nil? || text.empty?)
					text = "Stat #{i}"
				end
				color = params["block#{i}_color"].to_s
				icon = params["block#{i}_icon"].to_s

				newStatBlocks << {:type => type, :rt => rt, :text => text, :color => color, :icon => icon}
			end

			dc.stats = newStatBlocks
		else
			settingsHash = Hash.new

			dc.customSettings.keys.each do |k|
				settingsHash[k] = {:name => dc.customSettings[k][:name], :val => params["custom_#{k}"]}
			end

			dc.customSettings = settingsHash
			dc.make_dirty(:customSettings)
		end

		dc.save

		redirect "/admin/dashConfigs/#{dc.id}"
	end

	get '/admin/flags/?' do
		@flags = Flag.all()

		erb :admin_flags
	end

	get '/admin/flags/new/?' do
		erb :admin_flag_new
	end

	post '/admin/flags/new/?' do
		name = params[:name].to_s
		desc = params[:desc].to_s
		icon = params[:icon].to_s
		active = (!params[:isActive].nil?)

		if(name.strip.empty?)
			redirect "/admin/flags/new"
		end

		if(!Flag.first(:name => name).nil?)
			@errstr = "Flag with that name already exists"
			return erb :error
		end

		flag = Flag.create(:name => name, :description => desc, :icon => icon, :active => active)

		redirect "/admin/flags/#{flag.id}"
	end

	get '/admin/flags/:fid/?' do
		fid = params[:fid].to_i

		@flag = Flag.get(fid)
		if(@flag.nil?)
			@errstr = "Unable to find Flag"
			return erb :error
		end

		erb :admin_flag_single
	end

	post '/admin/flags/:fid/?' do
		fid = params[:fid].to_i

		flag = Flag.get(fid)
		if(flag.nil?)
			@errstr = "Unable to find Flag"
			return erb :error
		end

		name = params[:name].to_s
		desc = params[:desc].to_s
		icon = params[:icon].to_s
		active = (!params[:isActive].nil?)

		curFlag = Flag.first(:name => name)
		if(!curFlag.nil? && curFlag.id != fid)
			@errstr = "Flag with that name already exists"
			return erb :error
		end

		flag.name = name unless name.empty?
		flag.description = desc
		flag.icon = icon
		flag.active = active

		flag.save

		redirect "/admin/flags/#{flag.id}"
	end

	get '/admin/flags/:fid/delete/?' do
		fid = params[:fid].to_i

		@flag = Flag.get(fid)
		if(@flag.nil?)
			@errstr = "Unable to find Flag"
			return erb :error
		end

		erb :admin_flag_delete_conf
	end

	post '/admin/flags/:fid/delete/?' do
		fid = params[:fid].to_i

		flag = Flag.get(fid)
		if(flag.nil?)
			@errstr = "Unable to find Flag"
			return erb :error
		end

		confirm = false
		if(params[:confirm].downcase == "confirm")
			confirm = true
		end

		if(!confirm)
			redirect "/admin/flags/#{flag.id}"
			return
		else
			flag.application_flags.destroy
			flag.destroy

			redirect "/admin/flags"
		end
	end

	get '/admin/vulnSources/?' do
		@sources = VulnSource.all()

		erb :admin_vs
	end

	get '/admin/vulnSources/new/?' do
		erb :admin_vs_new
	end

	post '/admin/vulnSources/new/?' do
		name = params[:name].to_s
		shortname = params[:shortname].to_s.strip
		desc = params[:desc].to_s
		enabled = (!params[:isEnabled].nil?)

		if(name.strip.empty?)
			redirect "/admin/vulnSources/new"
		end

		if(!VulnSource.first(:name => name).nil?)
			@errstr = "Vuln Source with that name already exists"
			return erb :error
		end

		vs = VulnSource.create(:name => name, :shortname => shortname, :description => desc, :enabled => enabled)

		redirect "/admin/vulnSources/#{vs.id}"
	end

	get '/admin/vulnSources/:vsid/?' do
		vsid = params[:vsid].to_i

		@vs = VulnSource.get(vsid)
		if(@vs.nil?)
			@errstr = "Unable to find Vuln Source"
			return erb :error
		end

		erb :admin_vs_single
	end

	post '/admin/vulnSources/:vsid/?' do
		vsid = params[:vsid].to_i

		vs = VulnSource.get(vsid)
		if(vs.nil?)
			@errstr = "Unable to find Vuln Source"
			return erb :error
		end

		name = params[:name].to_s
		shortname = params[:shortname].to_s.strip
		desc = params[:desc].to_s
		enabled = (!params[:isEnabled].nil?)

		curVs = VulnSource.first(:name => name)
		if(!curVs.nil? && curVs.id != vsid)
			@errstr = "Vuln Source with that name already exists"
			return erb :error
		end

		vs.name = name unless name.empty?
		vs.shortname = shortname unless shortname.empty?
		vs.description = desc
		vs.enabled = enabled

		vs.save

		redirect "/admin/vulnSources/#{vs.id}"
	end

	get '/admin/vulnSources/:vsid/delete/?' do
		vsid = params[:vsid].to_i

		@vs = VulnSource.get(vsid)
		if(@vs.nil?)
			@errstr = "Unable to find Vuln Source"
			return erb :error
		end

		erb :admin_vs_delete_conf
	end

	post '/admin/vulnSources/:vsid/delete/?' do
		vsid = params[:vsid].to_i

		vs = VulnSource.get(vsid)
		if(vs.nil?)
			@errstr = "Unable to find Vuln Source"
			return erb :error
		end

		confirm = false
		if(params[:confirm].downcase == "confirm")
			confirm = true
		end

		if(!confirm)
			redirect "/admin/vulnSources/#{vs.id}"
			return
		else
			Vulnerability.all(:vulnSource => vs.id).each do |v|
				v.vulnSource = v.vtobj.defaultSource
				v.save
			end

			vs.destroy

			redirect "/admin/vulnSources"
		end
	end

end