##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

class Vulnreport < Sinatra::Base
	
	get '/reviews/:aid/relink/?' do
		@app = Application.get(params[:aid])
		if(@app.nil?)
			@errstr = "Application not found"
			return erb :error 
		end

		if(!@app.recordType.isLinked)
			@errstr = "Record Type does not use a Linked Object"
			return erb :error
		end

		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		erb :app_relink
	end

	post '/reviews/:aid/relink/?' do
		@app = Application.get(params[:aid])
		if(@app.nil?)
			@errstr = "Application not found"
			return erb :error 
		end

		if(!@app.recordType.isLinked)
			@errstr = "Record Type does not use a Linked Object"
			return erb :error
		end

		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		eid = params[:eid]
		validateResult = @app.getVRLO.validateEntityID(eid, @app)

		if(!validateResult[:valid])
			@errstr = "Invalid Entity ID: #{validateResult[:errstr]}"
			return erb :error
		else
			eid = validateResult[:eid]

			#Destroy old links
			Link.all(:fromType => LINK_TYPE::APPLICATION, :fromId => @app.id, :toType => LINK_TYPE::VRLO).each do |link|
				AuditRecord.create(:event_at => DateTime.now, :event_type => EVENT_TYPE::APP_UNLINK, :actor => session[:uid], :target_a_type => LINK_TYPE::APPLICATION, 
								   :target_a => @app.id, :target_b_type => LINK_TYPE::VRLO, :target_b => link.toId)
				link.destroy!
			end

			#Create new link
			newLink = Link.create(:fromType => LINK_TYPE::APPLICATION, :fromId => @app.id, :toType => LINK_TYPE::VRLO, :toId => eid)
			AuditRecord.create(:event_at => DateTime.now, :event_type => EVENT_TYPE::APP_LINK, :actor => session[:uid], :target_a_type => LINK_TYPE::APPLICATION, 
							   :target_a => @app.id, :target_b_type => LINK_TYPE::VRLO, :target_b => newLink.toId, :details_txt => @app.getVRLO.vrlo_name)
		end
		
		redirect "/reviews/#{@app.id}"
	end

	get '/reviews/new/?' do
		halt 401, (erb :unauth) if reports_only?

		rts = getAllowedRTObjsForUser(@session[:uid])
		@appRecordTypes = Array.new
		rts.each do |rt|
			if(rt.active)
				@appRecordTypes << rt
			end
		end
		@defaultGeo = User.get(@session[:uid]).defaultGeo
		@users = User.activeSorted()

		erb :app_create
	end

	post '/reviews/new/?' do
		halt 401, (erb :unauth) if reports_only?

		newName = params[:appName].strip
		newDesc = params[:appDescr].strip
		newRecordType = params[:recordType].to_i
		newOwner = params[:owner].to_i
		newGeo = params[:geo].to_i

		if(newOwner == 0)
			newOwner = nil
		end

		if(!newOwner.nil? && newOwner != 0)
			newOwnerUser = User.get(newOwner)
			newOwnerName = newOwnerUser.name
		end

		rt = RecordType.get(newRecordType)
		if(rt.nil? || !getAllowedRTsForUser(@session[:uid]).include?(newRecordType))
			@errstr = "Invalid RecordType"
			return erb :error
		end

		if(!rt.canBePassedToCon && !newOwner.nil? && newOwnerUser.contractor?)
			@errstr = "Invalid Owner - RecordType cannot be assigned to contractor"
			return erb :error
		end

		a = Application.create(:record_type => newRecordType, :name => newName, :description => newDesc, :geo => newGeo, :org_created => session[:org], :owner => newOwner)
		logAudit(EVENT_TYPE::APP_CREATE, LINK_TYPE::APPLICATION, a.id)
		logAudit(EVENT_TYPE::APP_OWNER_ASSIGN, LINK_TYPE::APPLICATION, a.id, {:userName => newOwnerName}) unless newOwnerName.nil?
		logAudit(EVENT_TYPE::APP_GEO_SET, LINK_TYPE::APPLICATION, a.id, {:geoId => newGeo})

		if(rt.defaultPrivate)
			a.isPrivate = true
			a.allow_UIDs = [@session[:uid]]
			a.save
			logAudit(EVENT_TYPE::APP_MADE_PRIVATE, LINK_TYPE::APPLICATION, a.id)
		end

		if(a.recordType.isLinked)
			vrlo = a.getVRLO
			begin
				vrloResult = vrlo.doCreateAppActions(a, @session[:uid])
			rescue Exception => e
				Rollbar.error(e, "Unable to perform VRLO Create App Actions", {:vrlo_key => vrlo.vrlo_key, :aid => a.id})
				vrloResult = {:success => false, :errstr => "Exception while performing Linked Object actions"}
			end
		end

		redirect "/reviews/#{a.id}"
	end

	get '/reviews/my/?' do
		redirect "/reviews/my/all/all/all"
	end

	post '/reviews/my/?' do
		datestring = (params[:alldata]) ? "all" : form_datestring(params[:startdate], params[:enddate])
		flags = form_flagstring(params[:appFlags], params[:flagSelectAll])
		rtStr = form_rtstring(params[:recordTypes], params[:rtSelectAll])

		redirect "/reviews/my/#{datestring}/#{flags}/#{rtStr}"
	end

	get '/reviews/my/:period/:flags/:rt/?' do
		@formsub = "/reviews/my/"
		@intervals = []

		@selectedFlags, @appTypeString = parseFlags(params[:flags])
		@startdate, @enddate, @periodString = parsePeriod(params[:period])
		@selectedRecordTypes = parseRt(params[:rt])

		@myActiveReviews = Array.new
		@myPastReviews = Array.new
		addedReviews = Array.new

		@user = User.get(session[:uid])

		Test.allWithFlags(@selectedFlags, :complete => false, :reviewer => @user.id, :order => [ :id.asc ], :created_at => (@startdate..@enddate), Test.application.record_type => @selectedRecordTypes).each do |t|
			next if(addedReviews.include?(t.application_id))
			next if(!canViewReview?(t.application_id))

			@myActiveReviews << {:app => Application.get(t.application_id), :test => t}
			addedReviews << t.application_id
		end

		Test.allWithFlags(@selectedFlags, :complete => true, :reviewer => @user.id, :order => [ :id.desc ], :created_at => (@startdate..@enddate), Test.application.record_type => @selectedRecordTypes).each do |t|
			next if(addedReviews.include?(t.application_id))
			next if(!canViewReview?(t.application_id))

			@myPastReviews << {:app => Application.get(t.application_id), :test => t}
			addedReviews << t.application_id
		end

		erb :app_list_my
	end

	get '/reviews/active/?' do
		redirect "/reviews/active/default/all/all"
	end

	post '/reviews/active/?' do
		datestring = (params[:alldata]) ? "all" : form_datestring(params[:startdate], params[:enddate])
		flags = form_flagstring(params[:appFlags], params[:flagSelectAll])
		rtStr = form_rtstring(params[:recordTypes], params[:rtSelectAll])

		redirect "/reviews/active/#{datestring}/#{flags}/#{rtStr}"
	end

	get '/reviews/active/:period/:flags/:rt?' do
		@formsub = "/reviews/active/"
		@intervals = []

		@selectedFlags, @appTypeString = parseFlags(params[:flags])
		@startdate, @enddate, @periodString = parsePeriod(params[:period], Date.today.beginning_of_year)
		@selectedRecordTypes = parseRt(params[:rt])

		@activeReviews = Array.new
		addedReviews = Array.new

		Test.allWithFlags(@selectedFlags, :complete => false, :order => [ :id.asc ], :created_at => (@startdate..@enddate), Test.application.record_type => @selectedRecordTypes).each do |t|
			next if(addedReviews.include?(t.application_id))
			next if(!canViewReview?(t.application_id))

			@activeReviews << {:app => Application.get(t.application_id), :test => t}
			addedReviews << t.application_id
		end

		@user = User.get(session[:uid])

		erb :app_active_list
	end

	get '/reviews/all/?' do
		redirect "/reviews/all/all/all/all/?os=0"
	end

	post '/reviews/all/?' do
		datestring = (params[:alldata]) ? "all" : form_datestring(params[:startdate], params[:enddate])
		flags = form_flagstring(params[:appFlags], params[:flagSelectAll])
		rtStr = form_rtstring(params[:recordTypes], params[:rtSelectAll])

		redirect "/reviews/all/#{datestring}/#{flags}/#{rtStr}/?os=0"
	end

	get '/reviews/all/:period/:flags/:rt/?' do
		@formsub = "/reviews/all/"
		@intervals = []

		period = params[:period].downcase
		@selectedFlags, @appTypeString = parseFlags(params[:flags])
		@startdate, @enddate, @periodString = parsePeriod(period)
		@selectedRecordTypes = parseRt(params[:rt])

		#Offset parse
		lim = 50

		if(params[:os].nil?)
			offset = 0
		else
			offset = params[:os].to_i
		end
		@total = Application.countWithFlags(@selectedFlags, :record_type => @selectedRecordTypes, :created_at => (@startdate..@enddate))

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

		@reviews = Array.new

		Application.allWithFlags(@selectedFlags, :record_type => @selectedRecordTypes, :created_at => (@startdate..@enddate), :limit => lim, :offset => offset, :order => [ :id.desc ]).each do |a|
			if(a.isPrivate)
				next if !canViewReview?(a.id)
			end

			@reviews << a
		end

		erb :app_all_list
	end

	get '/reviews/:aid/?' do
		cache = true
		if(params['cacheref'] == '1')
			cache = false
		end
		
		@app = Application.get(params[:aid])
		if(@app.nil?)
			@errstr = "Application not found"
			return erb :error 
		end

		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		#By the time we get here, this only evals true for Admins or maybe Supers
		if(@app.isPrivate && !userAllowedForApp(@session[:uid], @app.id) && !userWarnedForApp?(@session[:uid], @app.id))
			if(params[:warned] == "true")
				markUserWarnedApp(@session[:uid], @app.id)
				redirect "/reviews/#{@app.id}"
			else
				@tid = nil
				@aid = @app.id
				return erb :app_private_warning
			end
		end

		@pageTitle = @app.name
		@tests = @app.tests

		@comments = Comment.commentsForApp(@app.id, @session[:uid], @session[:org])
		@unreadComments = 0
		@comments.each do |c|
			@unreadComments += 1 if(c.isUnseen?(session[:uid]))
		end

		if(!params[:fromNotif].nil?)
			@fromNotif = true
		end

		if(RecordType.get(@app.record_type).isLinked)
			if(@app.isLinked?)
				begin
					vrloPanel = @app.linkedObjectInfoPanel(@session[:uid], params, env)
				rescue Exception => e
					Rollbar.error(e, "Unable to generate VRLO Info Panel", {:vrlo_key => @app.getVRLO.vrlo_key, :aid => @app.id, :vrlo_eid => @app.linkId})
					vrloPanel = {:success => false, :errstr => "Exception while getting Linked Object data. Exception logged."}
				end

				if(!vrloPanel[:success])
					@vrloError = true
					@vrloErrorStr = vrloPanel[:errstr]
					@VRLOInfoPanelHTML = nil
					@VRLOAlerts = nil
					@VRLOMenuItems = nil
				else
					@VRLOInfoPanelHTML = vrloPanel[:infoPanelHtml]
					@VRLOAlerts = vrloPanel[:alerts]
					
					@VRLOMenuItems = Array.new
					menuItems = vrloPanel[:customMenuItems]
					#check auth for each
					menuItems.each do |m|
						authOk = true
						if(!m[:authMethods].nil? && m[:authMethods].size > 0)
							m[:authMethods].each do |am|
								amMethod = am[0]
								amArgs = am[1]
								begin
									if(!amArgs.nil? && amArgs.size > 0)
										amResult = send(amMethod, amArgs)
									else
										amResult = send(amMethod)
									end
								rescue
									authOk = false
								end

								if(!amResult)
									authOk = false
								end
							end
						end

						if(authOk)
							@VRLOMenuItems << m
						end
					end
				end
			else
				@unlinkedApp = true
				@VRLOInfoPanelHTML = nil
				@VRLOAlerts = nil
				@VRLOMenuItems = nil
			end
		else
			@unlinkedApp = false
			@VRLOInfoPanelHTML = nil
			@VRLOAlerts = nil
			@VRLOMenuItems = nil
		end
		
		erb :app_single
	end

	get '/reviews/:aid/audit/?' do
		@app = Application.get(params[:aid])
		if(@app.nil?)
			@errstr = "Application not found"
			return erb :error 
		end

		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		#By the time we get here, this only evals true for Admins or maybe Supers
		if(@app.isPrivate && !userAllowedForApp(@session[:uid], @app.id) && !userWarnedForApp?(@session[:uid], @app.id))
			if(params[:warned] == "true")
				markUserWarnedApp(@session[:uid], @app.id)
				redirect "/reviews/#{@app.id}/audit"
			else
				@tid = nil
				@aid = @app.id
				return erb :app_private_warning
			end
		end

		@pageTitle = @app.name

		@comments = Comment.commentsForApp(@app.id, @session[:uid], @session[:org])
		@unreadComments = 0
		@comments.each do |c|
			@unreadComments += 1 if(c.isUnseen?(session[:uid]))
		end

		#Get audit items together and sort
		@audits = AuditRecord.getAppAudits(@app.id)

		erb :app_audit
	end

	get '/reviews/:aid/raw/?' do
		only_admins!

		@app = Application.get(params[:aid])
		if(@app.nil?)
			@errstr = "Application not found"
			return erb :error 
		end

		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		erb :app_raw
	end

	get '/reviews/:aid/permCheck/?' do
		only_admins!

		@app = Application.get(params[:aid])
		if(@app.nil?)
			@errstr = "Application not found"
			return erb :error 
		end

		@orgs = Array.new
		@users = Array.new

		Organization.all().each do |o|
			@orgs << {:org => o, :access => orgAllowedRT?(o.id, @app.record_type)}
		end

		User.all(:active => true, :order => [:org.asc]).each do |u|
			@users << {:user => u, :org => Organization.get(u.org), :access => canViewReview?(@app.id, u.id)}
		end

		erb :app_perm_list
	end

	get '/reviews/:aid/edit/?' do
		@app = Application.get(params[:aid])
		if(@app.nil?)
			@errstr = "Application not found"
			return erb :error 
		end

		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		@pageTitle = @app.name
		@isGlobal = ""
		if(@app.global)
			@isGlobal = "checked"
		end

		@isPrivate = ""
		if(@app.isPrivate)
			@isPrivate = "checked"
		end

		@appRecordTypes = getAllowedRTObjsForUser(@session[:uid])

		@orgs = Organization.all()
		@users = User.activeSorted()
		@canPassToContractor = (@app.canPassToContractor? && canPassToContractor?(@app.id))
		@availableFlags = Flag.all(:active => true)

		erb :app_edit
	end

	post '/reviews/:aid/edit/?' do
		@app = Application.get(params[:aid])
		if(@app.nil?)
			@errstr = "Application not found"
			return erb :error 
		end

		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		@pageTitle = @app.name

		newName = params[:appName].strip
		nameChange = false
		if(!newName.nil? && newName != @app.name)
			nameChange = true
			oldName = @app.name
			@app.name = newName
		end

		newDesc = params[:appDescr].strip
		@app.description = newDesc unless newDesc.nil?

		@appRecordTypes = getAllowedRTObjsForUser(@session[:uid])
		newRecordType = params[:recordType].to_i
		rtChange = false
		if(!(params[:recordType].nil? || newRecordType <= 0) && newRecordType != @app.record_type)
			rtChange = true
			oldRT = @app.recordTypeName
			@app.record_type = newRecordType
		end

		newOwner = params[:owner].to_i
		ownerChange = false
		if(!newOwner.nil? && newOwner != @app.owner)
			ownerChange = true
			if(newOwner == 0)
				newOwner = nil
			end

			if((!@app.canPassToContractor? || !canPassToContractor?(@app.id)) && !newOwner.nil?)
				newOwnerUser = User.get(newOwner)
				if(newOwnerUser.contractor?)
					ownerChange = false
					newOwner = @app.owner
				end
			end
			@app.owner = newOwner
		end

		newGeo = params[:geo].to_i
		geoChange = false
		if(!newGeo.nil? && newGeo != @app.geo)
			geoChange = true
			@app.geo = newGeo
		end

		newAddEmails = params[:addEmails].strip
		emails = newAddEmails.split(',')
		emails.each do |e|
			e = e.strip
			if(!isValidEmail?(e))
				@save_error = true
				@save_error_str = "Invalid email address - #{e}"
			end
		end
		@app.add_emails = newAddEmails unless newAddEmails.nil?

		newGlobal = false
		if (!params[:isGlobal].nil?)
			newGlobal = true
		end

		globalChange = false
		if(newGlobal != @app.global)
			globalChange = true
			@app.global = newGlobal
		end

		newPrivate = false
		if (!params[:isPrivate].nil?)
			newPrivate = true
		end

		privateChange = false
		if(newPrivate != @app.isPrivate)
			privateChange = true
			@app.isPrivate = newPrivate
		end

		allowedUIDs = Array.new
		if(!params[:userms].nil?)
			params[:userms].each do |uid|
				allowedUIDs << uid.to_i
			end
		end

		flagIds = Array.new
		if(!params[:flagms].nil?)
			params[:flagms].each do |fid|
				flagIds << fid.to_i
			end
		end

		curFlagIds = @app.flagIds
		Flag.all(:active => true).each do |f|
			if(flagIds.include?(f.id) && !curFlagIds.include?(f.id))
				@app.flags << f
				logAudit(EVENT_TYPE::APP_FLAG_ADD, LINK_TYPE::APPLICATION, @app.id, {:flagName => f.name})
			elsif(!flagIds.include?(f.id) && curFlagIds.include?(f.id))
				app_flag_link = @app.application_flags.first(:flag => f)
				app_flag_link.destroy
				logAudit(EVENT_TYPE::APP_FLAG_REM, LINK_TYPE::APPLICATION, @app.id, {:flagName => f.name})
				@app.reload
			end
		end

		if(@app.isPrivate && allowedUIDs.size == 0)
			allowedUIDs << session[:uid]
		end

		@app.allow_UIDs = allowedUIDs
		@orgs = Organization.all()
		@users = User.activeSorted()
		@canPassToContractor = (@app.canPassToContractor? && canPassToContractor?(@app.id))
		@availableFlags = Flag.all(:active => true)

		if(@app.save)
			if(nameChange)
				logAudit(EVENT_TYPE::APP_RENAME, LINK_TYPE::APPLICATION, @app.id, {:fromName => oldName, :toName => newName})
			end

			if(rtChange)
				logAudit(EVENT_TYPE::APP_RTCHANGE, LINK_TYPE::APPLICATION, @app.id, {:fromName => oldRT, :toName => @app.recordTypeName})
			end

			if(ownerChange)
				if(newOwner.nil? || newOwner == 0)
					newOwnerName = "Unassigned"
				else
					newOwnerName = User.get(newOwner).name
				end
				logAudit(EVENT_TYPE::APP_OWNER_ASSIGN, LINK_TYPE::APPLICATION, @app.id, {:userName => newOwnerName})

				if(@app.recordType.isLinked && @app.isLinked?)
					vrlo = @app.getVRLO
					begin
						vrloResult = vrlo.doAppReassignedActions(@app, @session[:uid], newOwner)
					rescue Exception => e
						Rollbar.error(e, "Unable to perform VRLO Create App Actions", {:vrlo_key => vrlo.vrlo_key, :aid => @app.id})
						vrloResult = {:success => false, :errstr => "Exception while performing Linked Object actions"}
					end
				end
			end

			if(geoChange)
				logAudit(EVENT_TYPE::APP_GEO_SET, LINK_TYPE::APPLICATION, @app.id, {:geoId => @app.geo})
			end

			if(globalChange)
				if(@app.global)
					logAudit(EVENT_TYPE::APP_MADE_GLOBAL, LINK_TYPE::APPLICATION, @app.id)
				else
					logAudit(EVENT_TYPE::APP_MADE_NOTGLOBAL, LINK_TYPE::APPLICATION, @app.id)
				end
			end

			if(privateChange)
				if(@app.isPrivate)
					logAudit(EVENT_TYPE::APP_MADE_PRIVATE, LINK_TYPE::APPLICATION, @app.id)
				else
					logAudit(EVENT_TYPE::APP_MADE_NOTPRIVATE, LINK_TYPE::APPLICATION, @app.id)
				end
			end

			if(@save_error)
				erb :app_edit
			else
				redirect "/reviews/#{@app.id}"
			end
		else
			@save_error = true
			erb :app_edit
		end
	end

	get '/reviews/:aid/unlink/?' do
		@app = Application.get(params[:aid])
		if(@app.nil?)
			@errstr = "Application not found"
			return erb :error 
		end

		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		if(!@app.recordType.isLinked)
			@errstr = "Record Type does not use a Linked Object"
			return erb :error
		end

		if(!@app.isLinked?)
			@errstr = "This application is not linked"
			return erb :error
		end		

		erb :app_confirm_unlink
	end

	post '/reviews/:aid/unlink/?' do
		@app = Application.get(params[:aid])
		if(@app.nil?)
			@errstr = "Application not found"
			return erb :error 
		end

		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		if(!@app.recordType.isLinked)
			@errstr = "Record Type does not use a Linked Object"
			return erb :error
		end

		if(!@app.isLinked?)
			@errstr = "This application is not linked"
			return erb :error
		end

		confirm = false
		if(params[:confirm].downcase == "confirm")
			confirm = true
		end

		if(!confirm)
			redirect "/reviews/#{@app.id}"
			return
		else
			Link.all(:fromType => LINK_TYPE::APPLICATION, :fromId => @app.id, :toType => LINK_TYPE::VRLO).each do |link|
				AuditRecord.create(:event_at => DateTime.now, :event_type => EVENT_TYPE::APP_UNLINK, :actor => session[:uid], :target_a_type => LINK_TYPE::APPLICATION, 
								   :target_a => @app.id, :target_b_type => LINK_TYPE::VRLO, :target_b => link.toId)
				link.destroy!
			end
			redirect "/reviews/#{@app.id}"
		end
	end

	get '/reviews/:aid/delete/?' do
		@app = Application.get(params[:aid])
		if(@app.nil?)
			@errstr = "Application not found"
			return erb :error 
		end

		halt 401, (erb :unauth) if(!canViewReview?(@app.id))
		halt 401, (erb :unauth) if(!canDeleteReview?(@app.id))

		erb :app_confirm_delete
	end

	post '/reviews/:aid/delete/?' do
		@app = Application.get(params[:aid])
		if(@app.nil?)
			@errstr = "Application not found"
			return erb :error 
		end

		halt 401, (erb :unauth) if(!canViewReview?(@app.id))
		halt 401, (erb :unauth) if(!canDeleteReview?(@app.id))

		confirm = false
		if(params[:confirm].downcase == "confirm")
			confirm = true
		end

		if(!confirm)
			redirect "/reviews/#{@app.id}"
			return
		else
			#destroy all links
			Link.all(:fromType => LINK_TYPE::APPLICATION, :fromId => @app.id).each do |link|
				link.destroy!
			end

			@app.tests.each do |test|
				test.vulnerabilities.each do |v|
					v.sections.each do |s|
						s.destroy!
					end
					v.destroy!
				end
				test.destroy!
			end

			if(@app.recordType.isLinked)
				vrlo = @app.getVRLO
				begin
					vrloResult = vrlo.doDeleteAppActions(@app, @session[:uid])
				rescue Exception => e
					Rollbar.error(e, "Unable to perform VRLO Delete App Actions", {:vrlo_key => vrlo.vrlo_key, :aid => @app.id})
					vrloResult = {:success => false, :errstr => "Exception while performing Linked Object actions"}
				end
			end

			@app.destroy!

			logAudit(EVENT_TYPE::APP_DELETE, LINK_TYPE::APPLICATION, params[:aid])
			redirect "/"
		end
	end

end