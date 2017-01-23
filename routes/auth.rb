##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

class Vulnreport < Sinatra::Base
	
	################
	#  SAML / SSO  #
	################

	def saml_settings
	  settings = OneLogin::RubySaml::Settings.new
	  settings.assertion_consumer_service_url = "/saml/finalize"
	  settings.issuer                         = getSetting('AUTH_SSO_ISSUER')
	  settings.idp_sso_target_url             = getSetting('AUTH_SSO_TARGET_URL')
	  settings.idp_cert_fingerprint           = getSetting('AUTH_SSO_CERT_FINGERPRINT')
	  settings.name_identifier_format         = "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"

	  settings
	end

	get '/login/?' do
		if(!session[:login_error].nil?)
			@login_error = true
			@login_error_str = session[:login_error]
			session[:login_error] = nil
		elsif(session[:logout_complete])
			@logout_success = true
			session.clear
		end

		seeded = getSetting('VR_SEEDED')
		if(seeded.nil? || seeded != 'true')
			@login_error = true
			@login_error_str = "Vulnreport has not been seeded"
			@login_auth = true
		else		
			@login_auth = (getSetting('AUTH_LOGIN_ENABLED') == 'true')
			redirect "/saml/login" if (!@login_auth && session[:login_error].nil? && !@logout_success)

			@sso_auth = (getSetting('AUTH_SSO_ENABLED') == 'true')
			if(@sso_auth)
				@sso_name = getSetting('AUTH_SSO_NAME').strip
				@sso_name = "SSO" if(@sso_name.nil? || @sso_name.empty?)
			end
		end
			
		erb :auth_login
	end

	post '/login/?' do
		@login_auth = (getSetting('AUTH_LOGIN_ENABLED') == 'true')
		redirect "/saml/login" if (!@login_auth)

		loginIp = env['HTTP_X_FORWARDED_FOR'] || env['HTTP_X_REAL_IP'] || request.ip

		user = params[:username].strip.to_s
		pass = params[:password].strip.to_s

		if(user.nil? || pass.nil? || user.empty? || pass.empty?)
			session[:login_error] = "Username and Password required"
		else
			user = User.first(:username => user)
			if(user.nil?)
				session[:login_error] = "Invalid User/Pass"
			else
				if(user.password == pass)
					if(!user.active)
						logAudit(EVENT_TYPE::USER_LOGIN_FAILURE, LINK_TYPE::USER, user.id, {:type => 'direct', :ip => loginIp, :ua => request.user_agent, :error => "inactive"}, user.id)
						session[:login_error] = "User account inactive - please contact your admin"
					else
						#Do login
						session[:logged_in] = true
						session[:uid] = user.id
						session[:org] = user.org
						session[:username] = user.username
						session[:email] = user.email
						session[:clipboard] = nil
						session[:geo] = user.defaultGeo
						if(user.name.nil?)
							session[:name] = user.username
							session[:loginredir] = "/usersettings"
						else
							session[:name] = user.name
							if(user.initials.nil?)
								session[:initials] = user.name.split(" ").collect{ |x| x[0] }.join("")
							else
								session[:initials] = user.initials
							end
						end

						logAudit(EVENT_TYPE::USER_LOGIN, LINK_TYPE::USER, user.id, {:type => 'direct', :ip => loginIp, :ua => request.user_agent}, user.id)

						if(session[:loginredir].nil? || session[:loginredir].strip.empty?)
							redirect "/"
						else
							redirect session[:loginredir]
						end
					end
				else
					logAudit(EVENT_TYPE::USER_LOGIN_FAILURE, LINK_TYPE::USER, user.id, {:type => 'direct', :ip => loginIp, :ua => request.user_agent, :error => "pw"}, user.id)
					session[:login_error] = "Invalid User/Pass"	
				end
			end
		end

		redirect "/login"
	end

	get "/saml/login/?" do
	    settings = saml_settings
	    request = OneLogin::RubySaml::Authrequest.new
	    redirect request.create(settings)
	end

	post "/saml/finalize/?" do
		response  = OneLogin::RubySaml::Response.new(params[:SAMLResponse])
	    response.settings = saml_settings
	    loginIp = env['HTTP_X_FORWARDED_FOR'] || env['HTTP_X_REAL_IP'] || request.ip

		if response.is_valid? && (!response.name_id.empty?)
			user = User.first(:sso_user => response.name_id)
			newUserRedir = false
			if(user.nil?)
				#User is not registered with Vulnreport yet
				if(getSetting('AUTO_ADD_USERS') == 'true')
					#Will auto-add user, still needs approval
					newuser = User.new(:sso_user => response.name_id, :username => response.name_id, :email => response.attributes[:email], :sso_id => response.attributes[:userId], :org => 0, :active => true, :admin => false, :defaultGeo => GEO::USA)
					if(newuser.save)
						#good to go
						session[:logged_in] = true
						session[:uid] = User.first(:sso_user => response.name_id).id
						session[:org] = 0
						session[:username] = response.name_id
						session[:email] = response.attributes[:email]
						session[:name] = response.name_id.split('@').first
						session[:initials] = ""
						session[:clipboard] = nil
						session[:loginredir] = "/usersettings"
						session[:geo] = GEO::USA
						newUserRedir = true

						logAudit(EVENT_TYPE::USER_LOGIN, LINK_TYPE::USER, newuser.id, {:type => 'sso', :ip => loginIp, :ua => request.user_agent}, newuser.id)
					else
						Rollbar.error("Error creating new user from SSO", {:errors => newuser.errors.inspect, :sso_user => response.name_id})
						session[:login_error] = "There was an error creating your Vulnreport account. Please contact your Vulnreport admin."
						redirect "/login"
					end
				else
					#Not auto adding users. Fail.
					session[:login_error] = "A Vulnreport user account for you does not exist. Please contact your Vulnreport admin."
					redirect "/login"
				end
			else
				if(!user.active)
					logAudit(EVENT_TYPE::USER_LOGIN_FAILURE, LINK_TYPE::USER, user.id, {:type => 'sso', :ip => loginIp, :ua => request.user_agent, :error => "inactive"}, user.id)
					session[:login_error] = "Your user account is inactive. Please contact your Vulnreport admin."
					redirect "/login"
				else
					#good to go
					session[:logged_in] = true
					session[:uid] = user.id
					session[:org] = user.org
					session[:username] = user.sso_user
					session[:email] = user.email
					session[:clipboard] = nil
					session[:geo] = user.defaultGeo
					if(user.name.nil?)
						session[:name] = user.sso_user.split('@').first
						session[:loginredir] = "/usersettings"
					else
						session[:name] = user.name
						if(user.initials.nil?)
							session[:initials] = user.name.split(" ").collect{ |x| x[0] }.join("")
						else
							session[:initials] = user.initials
						end
					end
					logAudit(EVENT_TYPE::USER_LOGIN, LINK_TYPE::USER, user.id, {:type => 'sso', :ip => loginIp, :ua => request.user_agent}, user.id)
				end
			end
			
			if(session[:loginredir].nil? || session[:loginredir].strip.empty?)
				if(newUserRedir)
					redirect "/usersettings"
				else
					redirect "/"
				end
			else
				redirect session[:loginredir]
			end
	    else
		   session[:logged_in] = false
		   session[:login_error] = "There was a problem logging in."
		   redirect "/login"
		end
	end

	get "/logout/?" do
		session[:logged_in] = false
		session[:uid] = nil
		session[:org] = nil
		session[:username] = nil
		session[:email] = nil
		session[:name] = nil
		session[:clipboard] = nil
		session[:geo] = nil
		session.clear

		session[:logout_complete] = true
		redirect "/login"
	end
end