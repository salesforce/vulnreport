##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

class Vulnreport < Sinatra::Base

	get '/tests/newfromapp/:aid/?' do
		@app = Application.get(params[:aid])
		if(@app.nil?)
			@errstr = "Application not found"
			return erb :error 
		end

		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		#See if theres already an active test for this app
		@app.tests.each do |ct|
			if(!ct.complete)
				#found one in progress
				redirect "/tests/#{ct.id}"
				return
			end
		end

		num = (@app.tests.count+1).to_s
		u = User.get(session[:uid])
		test = @app.tests.new(:reviewer => session[:uid], :name => "Test #{num}", :org_created => u.org)
		
		if(contractor?)
			test.contractor_test = true
		end

		ownerChange = false
		if(@app.owner.nil? || @app.owner == 0)
			@app.owner = session[:uid]
			ownerChange = true
		end

		@app.save
		logAudit(EVENT_TYPE::TEST_CREATE, LINK_TYPE::TEST, test.id)
		logAudit(EVENT_TYPE::TEST_REVIEWER_ASSIGNED, LINK_TYPE::TEST, test.id, {:userName => u.name})
		if(ownerChange)
			logAudit(EVENT_TYPE::APP_OWNER_ASSIGN, LINK_TYPE::APPLICATION, @app.id, {:userName => u.name})
		end

		if(@app.recordType.isLinked && @app.isLinked?)
			vrlo = @app.getVRLO
			begin
				vrloResult = vrlo.doNewTestActions(@app, test, @session[:uid])
			rescue Exception => e
				Rollbar.error(e, "Unable to perform VRLO New Test Actions", {:vrlo_key => vrlo.vrlo_key, :aid => @app.id, :vrlo_eid => @app.linkId})
				vrloResult = {:success => false, :errstr => "Exception while performing Linked Object actions"}
			end

			if(!vrloResult[:success])
				session[:errmsg] = "<b>Error:</b> Error performing linked object actions - #{vrloResult[:errstr]}"
			end

			if(!vrloResult[:alerts].nil?)
				session[:vrloAlerts] = vrloResult[:alerts]
			end
		end

		redirect "/tests/#{test.id}"
	end

	get '/tests/:tid/?' do
		@test = Test.get(params[:tid])
		if(@test.nil?)
			@errstr = "Test not found"
			return erb :error 
		end

		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		#By the time we get here, this only evals true for Admins or maybe Supers
		if(@app.isPrivate && !userAllowedForApp(@session[:uid], @app.id) && !userWarnedForTest?(@session[:uid], @test.id))
			if(params[:warned] == "true")
				markUserWarnedTest(@session[:uid], @test.id)
				redirect "/tests/#{@test.id}"
			else
				@tid = @test.id
				@aid = nil
				return erb :app_private_warning
			end
		end

		@vulnTypes = VulnType.getByRecordType(@app.record_type).sort{ |x,y| x.getLabel <=> y.getLabel}
		appFlagIds = @app.flags.map{|f| f.id}
		@vulnTypes.delete_if do |vt|
			if(!vt.requiredFlags.nil? && !vt.requiredFlags.empty?)
				delVt = true
				vt.requiredFlags.each do |fid|
					if(appFlagIds.include?(fid))
						delVt = false
					end
				end

				if(delVt)
					true
				end
			end
		end

		if(!@session[:errmsg].nil? && !@session[:errmsg].empty?)
			@error = @session[:errmsg]
			@session[:errmsg] = nil
		elsif(!@session[:sucmsg].nil? && !@session[:sucmsg].empty?)
			@success = @session[:sucmsg]
			@session[:sucmsg] = nil
		end

		if(!@session[:vrloAlerts].nil? && !@session[:vrloAlerts].empty?)
			@VRLOAlerts = @session[:vrloAlerts]
			@session[:vrloAlerts] = nil
		end

		@pageTitle = @app.name + " - " + @test.name
		@approver = nil
		if(@test.approved_by > 0)
			@approver = User.get(@test.approved_by)
		end

		@comments = Comment.commentsForTest(@test.id, @session[:uid], @session[:org])
		@unreadComments = 0
		@comments.each do |c|
			@unreadComments += 1 if(c.isUnseen?(session[:uid]))
		end

		if(!params[:fromNotif].nil?)
			@fromNotif = true
		end

		#Get vulnerabilities and subset if needed for pagination
		lim = 100

		if(params[:os].nil?)
			offset = 0
		else
			offset = params[:os].to_i
		end
		@vulns_total = @test.vulnerabilities.length

		@vulns_start = offset+1
		@vulns_end = (offset+lim > @vulns_total) ? @vulns_total : (offset+lim)

		@vulns_next = nil
		if(offset+lim < @vulns_total)
			@vulns_next = offset+lim
		end

		@vulns_last = nil
		if(offset > 0)
			@vulns_last = offset-lim
			if(@vulns_last < 0)
				@vulns_last = 0
			end
		end

		@vulns = @test.vulnerabilities.sort{ |x,y| x.vuln_priority <=> y.vuln_priority }[offset, lim]

		if(@app.recordType.isLinked && @app.isLinked?)
			if(@app.isLinked?)
				vrloInfo = @app.getVRLO.getTestAlerts(@app, @test, @session[:uid])
				if(!vrloInfo[:success])
					@errstr = "Error generating linked object information: #{vrloInfo[:errstr]}"
					return erb :error
				else
					if(@VRLOAlerts.nil?)
						@VRLOAlerts = vrloInfo[:alerts]
					else
						@VRLOAlerts.concat(vrloInfo[:alerts])
					end
					
					@VRLOMenuItems = Array.new
					menuItems = vrloInfo[:customMenuItems]
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
				@VRLOAlerts = nil
				@VRLOMenuItems = nil
			end
		else
			@VRLOAlerts = nil
			@VRLOMenuItems = nil
		end

		if(@test.provPassReq && !@test.provPass && !@test.complete)
			@provPassRequested = true
			ppReqAR = AuditRecord.last(:event_type => EVENT_TYPE::PROV_PASS_REQUEST, :target_a => @test.id)
			@ppReqUser = User.get(ppReqAR.actor)
			@ppReqTime = ppReqAR.event_at
			@ppReqJustif = ppReqAR.details_txt
		elsif(@test.provPass && @test.complete)
			@provPassApproved = true
			
			ppReqAR = AuditRecord.last(:event_type => EVENT_TYPE::PROV_PASS_REQUEST, :target_a => @test.id)
			@ppReqUser = User.get(ppReqAR.actor)
			@ppReqTime = ppReqAR.event_at
			@ppReqJustif = ppReqAR.details_txt

			ppApproveAR = AuditRecord.last(:event_type => EVENT_TYPE::PROV_PASS_APPROVE, :target_a => @test.id)
			@ppApprvUser = User.get(ppApproveAR.actor)
			@ppApprvTime = ppApproveAR.event_at
			@ppApprvNotes = ppApproveAR.details_txt
		end

		@pdf_on = false
		if(!getSetting('PDF_EXPORT_ON').nil? && getSetting('PDF_EXPORT_ON') == 'true')
			@pdf_on = true
		end

		erb :test_single
	end

	post '/tests/:tid/newvuln/?' do
		@test = Test.get(params[:tid])
		if(@test.nil?)
			@errstr = "Test not found"
			return erb :error 
		end

		halt 401, (erb :unauth) if(!canViewReview?(@test.application.id))

		if(params[:type] == "xml")
			redirect "/tests/#{@test.id}/xmlup"
		end

		type = params[:type].to_i
		if(type == 0 || (!params[:customType].strip.nil? && !params[:customType].strip.empty?))
			redirect "/tests/#{@test.id}" if params[:customType].strip.nil? || params[:customType].strip.empty?
			v = @test.vulnerabilities.new(:vulntype => 0, :custom => params[:customType])
		else
			vulnType = VulnType.get(type)
			if(!vulnType.nil?)
				v = @test.vulnerabilities.new(:vulntype => type, :vulnSource => vulnType.defaultSource)
			end
		end

		@test.save

		redirect "/tests/#{@test.id}/#{v.id}"
	end

	get '/tests/:tid/xmlup/?' do
		@test = Test.get(params[:tid])
		if(@test.nil?)
			@errstr = "Test not found"
			return erb :error 
		end

		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		erb :test_importxml
	end

	post '/tests/:tid/xmlup/?' do
		@test = Test.get(params[:tid])
		if(@test.nil?)
			@errstr = "Test not found"
			return erb :error 
		end

		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		xml = params[:xml]
		xmlFile = File.open(params[:xml][:tempfile], "rb")
		
		doc = Nokogiri::XML(xmlFile)

		doc.root.xpath("//Vuln").each do |v|
			type = v.at_xpath(".//Type")
			typeCode = type.children.first.text.to_i
			if(typeCode == 0)
				customType = v.at_xpath(".//CustomTypeName").children.first.text
				thisVuln = @test.vulnerabilities.create(:vulntype => 0, :custom => customType)
			else
				vulnType = VulnType.get(typeCode)
				if(vulnType.nil?)
					typeCode = 0
					vulnSource = 0
				else
					vulnSource = vulnType.defaultSource
				end
				thisVuln = @test.vulnerabilities.create(:vulntype => typeCode, :vulnSource => vulnSource)
			end

			v.element_children.each do |c|
				next if(c.name.upcase == "TYPE" || c.name.upcase == "TEXT" || c.name.upcase == "CUSTOMTYPENAME")

				if(c.name.upcase == "FILENAME")
					thisVuln.sections.create(:type => SECT_TYPE::FILE, :body => c.text)
				elsif(c.name.upcase == "URL")
					thisVuln.sections.create(:type => SECT_TYPE::URL, :body => c.text)
				elsif(c.name.upcase == "OUTPUT")
					thisVuln.sections.create(:type => SECT_TYPE::OUTPUT, :body => c.text)
				elsif(c.name.upcase == "CODE")
					thisVuln.sections.create(:type => SECT_TYPE::CODE, :body => c.text)
				elsif(c.name.upcase == "NOTES")
					thisVuln.sections.create(:type => SECT_TYPE::NOTES, :body => c.text)
				elsif(c.name.upcase == "SCREENSHOT")
					data = c.at_xpath(".//ImageData").text

					sshotSizeLimit = getSetting("SSHOT_MAX_SIZE_KB")
					sshotSizeLimit = (sshotSizeLimit.nil?) ? 1024 : sshotSizeLimit.to_i

					if(data.size > (sshotSizeLimit*1024))
						@session[:errmsg] = "Some images were not added as they were too large (Max size #{sshotSizeLimit} KB)"
						next
					end

					thisVuln.sections.create(:type => SECT_TYPE::SSHOT, :body => data)
				elsif(c.name.upcase == "PAYLOAD")
					data = c.at_xpath(".//PayloadData").text

					payloadSizeLimit = getSetting("PAYLOAD_MAX_SIZE_KB")
					payloadSizeLimit = (payloadSizeLimit.nil?) ? 1024 : payloadSizeLimit.to_i

					if(data.size > (payloadSizeLimit*1024))
						@session[:errmsg] = "Some payloads were not added as they were too large (Max size #{payloadSizeLimit} KB)"
						next
					end

					thisVuln.sections.create(:type => SECT_TYPE::PAYLOAD, :body => data)
				elsif(c.name.upcase == "BURPDATA")
					data = c.text
					result = data.scan(/<~=~=~=~=~=~=~=StartVulnReport:(.+?)=~=~=~=~=~=~=~>(.+?)<~=~=~=~=~=~=~=EndVulnReport:\1=~=~=~=~=~=~=~>/mi)
					result.each do |res|
						case res[0].downcase 
							when "url"
								thisVuln.sections.create(:type => SECT_TYPE::URL, :body => res[1])
							when "request"
								thisVuln.sections.create(:type => SECT_TYPE::CODE, :body => Base64.decode64(res[1]))
							when "response"
								thisVuln.sections.create(:type => SECT_TYPE::OUTPUT, :body => Base64.decode64(res[1]))
							else
								thisVuln.sections.create(:type => SECT_TYPE::NOTES, :body => res[1])
							end
					end
				end
			end
		end

		redirect "/tests/#{@test.id}"
	end

	get '/tests/:tid/edit/?' do
		@test = Test.get(params[:tid])
		if(@test.nil?)
			@errstr = "Test not found"
			return erb :error 
		end

		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		@isContractorTest = ""
		@isContractorComplete = ""
		@isContractorPass = ""
			
		@isContractorTest = "checked" if(@test.contractor_test)
		
		@rev = User.get(@test.reviewer)
		@users = User.all(:active => true)

		@pageTitle = @app.name + " - " + @test.name

		erb :test_edit
	end

	post '/tests/:tid/edit/?' do
		@test = Test.get(params[:tid])
		if(@test.nil?)
			@errstr = "Test not found"
			return erb :error 
		end

		newName = params[:testName].strip
		nameChange = false
		if(!newName.nil? && newName != @test.name)
			nameChange = true
			oldName = @test.name
			@test.name = newName
		end

		newDesc = params[:testDescr].strip
		@test.description = newDesc unless newDesc.nil?

		newRevId = params[:reviewer]
		revChange = false
		if(newRevId != @test.reviewer)
			revChange = true
			oldRevName = User.get(@test.reviewer).name
			newUser = User.get(newRevId)
			if(!newUser.nil?)
				@test.reviewer = newUser.id
			end
		end

		newConRev = false
		if (!params[:isContractorTest].nil?)
			newConRev = true
		end
		@test.contractor_test = newConRev

		newEid = params[:eid]
		@test.ext_eid = newEid

		if(@test.save)
			if(nameChange)
				logAudit(EVENT_TYPE::TEST_RENAME, LINK_TYPE::TEST, @test.id, {:fromName => oldName, :toName => newName})
			end

			if(revChange)
				logAudit(EVENT_TYPE::TEST_REVIEWER_UNASSIGNED, LINK_TYPE::TEST, @test.id, {:userName => oldRevName})
				logAudit(EVENT_TYPE::TEST_REVIEWER_ASSIGNED, LINK_TYPE::TEST, @test.id, {:userName => newUser.name})
			end

			redirect "/tests/#{@test.id}"
		else
			@save_error = true
			erb :test_edit
		end
	end

	get '/tests/:tid/pass/?' do
		@test = Test.get(params[:tid])
		if(@test.nil?)
			@errstr = "Test not found"
			return erb :error 
		end

		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id) || !canFinalizeTest?(@test.id))

		@color = "#009933"
		@newstatus = "passed"

		@disagree = false
		if(@test.is_pending && !@test.pending_pass)
			@disagree = true
		end

		@informational = false
		if(@test.verified_vulns.count > 0)
			@informational = true
		end

		erb :test_status_conf
	end

	get '/tests/:tid/fail/?' do
		@test = Test.get(params[:tid])
		if(@test.nil?)
			@errstr = "Test not found"
			return erb :error 
		end

		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id) || !canFinalizeTest?(@test.id))

		@color = "#B40404"
		@newstatus = "failed"

		@disagree = false
		if(@test.is_pending && @test.pending_pass)
			@disagree = true
		end

		erb :test_status_conf
	end

	get '/tests/:tid/inprog/?' do
		@test = Test.get(params[:tid])
		if(@test.nil?)
			@errstr = "Test not found"
			return erb :error 
		end

		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		@color = "#000"
		@newstatus = "in progress"

		erb :test_status_conf
	end

	post '/tests/:tid/updatestatus/?' do
		@test = Test.get(params[:tid])
		if(@test.nil?)
			@errstr = "Test not found"
			return erb :error 
		end

		@app = @test.application
		u = User.get(@session[:uid])
		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		confirm = false
		vrloActions = false
		status = "fail"

		if(params[:newstatus].downcase == "passed")
			status = "pass"
		elsif(params[:newstatus].downcase == "in progress")
			status = "inprog"
		end

		if (!params[:vrloActions].nil?)
			vrloActions = true
		end

		if(params[:confirm].downcase == "confirm")
			confirm = true
		end

		disagreeReason = nil
		if(!params[:disagreeReason].nil? && !params[:disagreeReason].empty?)
			disagreeReason = params[:disagreeReason]
		end

		if(!confirm)
			redirect "/tests/#{@test.id}"
			return
		else
			if(status == "pass")
				if(contractor?)
					@test.con_closed_at = Time.now
					@test.save
				end

				if(u.requiresApproval?)
					@test.is_pending = true
					@test.pending_at = Time.now
					@test.pending_by = @session[:uid]
					@test.pending_pass = true
					@test.complete = false
					@test.pass = false
					@test.save

					logAudit(EVENT_TYPE::TEST_PASS_REQ_APPROVAL, LINK_TYPE::TEST, @test.id)
				else
					@test.complete = true
					@test.pass = true
					@test.closed_at = Time.now
					@test.disagree_reason = disagreeReason if (!disagreeReason.nil?)
					@test.approved_by = @session[:uid]
					@test.is_pending = false
					@test.save

					logAudit(EVENT_TYPE::TEST_PASS, LINK_TYPE::TEST, @test.id)
				end

				if(@app.recordType.isLinked && @app.isLinked? && (contractor? || vrloActions))
					vrlo = @app.getVRLO
					begin
						vrloResult = vrlo.doPassActions(@app, @test, @session[:uid])
					rescue Exception => e
						Rollbar.error(e, "Unable to perform VRLO Pass Actions", {:vrlo_key => vrlo.vrlo_key, :aid => @app.id, :vrlo_eid => @app.linkId})
						vrloResult = {:success => false, :errstr => "Exception while performing Linked Object actions"}
					end

					if(!vrloResult[:success])
						session[:errmsg] = "<b>Error:</b> Error performing linked object actions - #{vrloResult[:errstr]}"
					end

					if(!vrloResult[:alerts].nil?)
						session[:vrloAlerts] = vrloResult[:alerts]
					end
				end
			elsif status == "inprog"
				if(contractor?)
					@test.contractor_test = true
					@test.con_closed_at = nil
					@test.save
				end

				@test.complete = false
				@test.closed_at = nil
				@test.pass = false
				@test.is_pending = false
				@test.pending_at = nil
				@test.pending_by = nil
				@test.pending_pass = false

				@test.save

				logAudit(EVENT_TYPE::TEST_INPROG, LINK_TYPE::TEST, @test.id)

				if(@app.recordType.isLinked && @app.isLinked? && (contractor? || vrloActions))
					vrlo = @app.getVRLO
					begin
						vrloResult = vrlo.doInProgressActions(@app, @test, @session[:uid])
					rescue Exception => e
						Rollbar.error(e, "Unable to perform VRLO In Progress Actions", {:vrlo_key => vrlo.vrlo_key, :aid => @app.id, :vrlo_eid => @app.linkId})
						vrloResult = {:success => false, :errstr => "Exception while performing Linked Object actions"}
					end

					if(!vrloResult[:success])
						session[:errmsg] = "<b>Error:</b> Error performing linked object actions - #{vrloResult[:errstr]}"
					end

					if(!vrloResult[:alerts].nil?)
						session[:vrloAlerts] = vrloResult[:alerts]
					end
				end
			else
				if(contractor?)
					@test.con_closed_at = Time.now
					@test.save
				end

				if(u.requiresApproval?)
					@test.is_pending = true
					@test.pending_at = Time.now
					@test.pending_by = @session[:uid]
					@test.pending_pass = false
					@test.complete = false
					@test.pass = false
					@test.save
					
					logAudit(EVENT_TYPE::TEST_FAIL_REQ_APPROVAL, LINK_TYPE::TEST, @test.id)
				else
					@test.complete = true
					@test.pass = false
					@test.closed_at = Time.now
					@test.disagree_reason = disagreeReason if (!disagreeReason.nil?)
					@test.approved_by = @session[:uid]
					@test.is_pending = false
					@test.save

					logAudit(EVENT_TYPE::TEST_FAIL, LINK_TYPE::TEST, @test.id)
				end

				if(@app.recordType.isLinked && @app.isLinked? && (contractor? || vrloActions))
					vrlo = @app.getVRLO
					begin
						vrloResult = vrlo.doFailActions(@app, @test, @session[:uid])
					rescue Exception => e
						Rollbar.error(e, "Unable to perform VRLO Fail Actions", {:vrlo_key => vrlo.vrlo_key, :aid => @app.id, :vrlo_eid => @app.linkId})
						vrloResult = {:success => false, :errstr => "Exception while performing Linked Object actions"}
					end

					if(!vrloResult[:success])
						session[:errmsg] = "<b>Error:</b> Error performing linked object actions - #{vrloResult[:errstr]}"
					end

					if(!vrloResult[:alerts].nil?)
						session[:vrloAlerts] = vrloResult[:alerts]
					end
				end
			end

			redirect "/tests/#{@test.id}"
		end
	end

	get '/tests/:tid/provPassRequest/?' do
		@test = Test.get(params[:tid])
		if(@test.nil?)
			@errstr = "Test not found"
			return erb :error 
		end

		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id) || !canFinalizeTest?(@test.id))
		halt 401, (erb :unauth) if(contractor?)

		if(!@app.recordType.canBeProvPassed)
			@errstr = "This Application cannot be Provisionally Passed"
			return erb :error
		end

		approvers = Array.new
		approversUsers = Array.new
		User.all(:provPassApprover => true, :active => true).each do |u|
			if(getAllowedRTsForUser(u.id).include?(@app.record_type))
				approversUsers << u
			end
		end
	
		approversUsers.each do |u|
			approvers << u.name
		end

		@ppApproversStr = approvers.join(", ")

		erb :test_prov_pass_request
	end

	post '/tests/:tid/provPassRequest' do
		@test = Test.get(params[:tid])
		if(@test.nil?)
			@errstr = "Test not found"
			return erb :error 
		end

		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id))
		halt 401, (erb :unauth) if(contractor?)

		if(!@app.recordType.canBeProvPassed)
			@errstr = "This Application cannot be Provisionally Passed"
			return erb :error
		end

		confirm = false
		if(params[:confirm].downcase == "confirm")
			confirm = true
		end
		if(!confirm)
			redirect "/tests/#{@test.id}"
			return
		end

		justificationText = params[:ppJustification]
		suggestedRemediation = params[:ppRemediation].to_i
		suggestedRemediation = 1 if(suggestedRemediation < 1 || suggestedRemediation > 3)

		#Create audit record
		ar = AuditRecord.create(:event_type => EVENT_TYPE::PROV_PASS_REQUEST, :event_at => DateTime.now, :actor => @session[:uid], :details_txt => justificationText, 
								:target_a_type => LINK_TYPE::TEST, :target_a => @test.id, :target_b_type => LINK_TYPE::APPLICATION, :target_b => @app.id)

		if(!ar.saved?)
			Rollbar.error("Error saving AuditRecord object", {:where => "prov pass request", :whatId => @test.id, :fault => ar.errors.to_s})
			@errstr = "Error requesting provisional pass (AuditRecord creation error)"
			erb :error
		end

		#set test. !complete  pass  provPassReq  !provPass
		#set test.provPassRequestor to UID
		@test.pass = true
		@test.provPassReq = true
		@test.provPassRequestor = @session[:uid]
		@test.provPassExpiry = Date.today >> suggestedRemediation
		if(!@test.save)
			Rollbar.error("Error saving Test object", {:where => "prov pass request", :fault => @test.errors.to_s})
			@errstr = "Error requesting provisional pass (Test record save error)"
			erb :error
		end

		#Send out notifications to approvers
		approversUsers = Array.new
		User.all(:provPassApprover => true, :active => true).each do |u|
			if(getAllowedRTsForUser(u.id).include?(@app.record_type))
				approversUsers << u
			end
		end

		if(!approversUsers.nil?)
			approversUsers.each do |u|
				Notification.create(:uidToNotify => u.id, :what => LINK_TYPE::TEST, :whatId => @test.id, :notifClass => NOTIF_CLASS::PROV_PASS_REQUEST)
			end
		end

		#redirect to test page with new status and test page shows info in header notif
		redirect "/tests/#{@test.id}"
	end

	get '/tests/:tid/cancelProvPassRequest/?' do
		@test = Test.get(params[:tid])
		if(@test.nil?)
			@errstr = "Test not found"
			return erb :error 
		end

		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id))
		halt 401, (erb :unauth) if(contractor?)

		ar = AuditRecord.last(:event_type => EVENT_TYPE::PROV_PASS_REQUEST, :target_a_type => LINK_TYPE::TEST, :target_a => @test.id)
		halt 401, (erb :unauth) if(ar.actor != @session[:uid] && !canApproveProvPass?)

		erb :test_cancel_prov_pass
	end

	post '/tests/:tid/cancelProvPassRequest' do
		@test = Test.get(params[:tid])
		if(@test.nil?)
			@errstr = "Test not found"
			return erb :error 
		end

		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id))
		halt 401, (erb :unauth) if(contractor?)

		confirm = false
		if(params[:confirm].downcase == "confirm")
			confirm = true
		end
		if(!confirm)
			redirect "/tests/#{@test.id}"
			return
		end

		ar = AuditRecord.last(:event_type => EVENT_TYPE::PROV_PASS_REQUEST, :target_a_type => LINK_TYPE::TEST, :target_a => @test.id)
		halt 401, (erb :unauth) if(ar.actor != @session[:uid] && !canApproveProvPass?)

		#set test. !complete  pass  provPassReq  !provPass
		#set test.provPassRequestor to UID
		@test.pass = false
		@test.provPassReq = false
		@test.provPassRequestor = nil
		@test.provPassExpiry = nil
		if(!@test.save)
			Rollbar.error("Error saving Test object", {:where => "prov pass cancel", :fault => @test.errors.to_s})
			@errstr = "Error cancelling provisional pass (Test record save error)"
			erb :error
		end

		ar = AuditRecord.create(:event_type => EVENT_TYPE::PROV_PASS_REQCANCEL, :event_at => DateTime.now, :actor => @session[:uid], 
								:target_a_type => LINK_TYPE::TEST, :target_a => @test.id, :target_b_type => LINK_TYPE::APPLICATION, :target_b => @app.id)

		#redirect to test page with new status and test page shows info in header notif
		redirect "/tests/#{@test.id}"
	end

	get '/tests/:tid/provPassApprove/?' do
		@test = Test.get(params[:tid])
		if(@test.nil?)
			@errstr = "Test not found"
			return erb :error 
		end

		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id))
		halt 401, (erb :unauth) if(!canApproveProvPass?)

		ppReqAR = AuditRecord.last(:event_type => EVENT_TYPE::PROV_PASS_REQUEST, :target_a => @test.id)
		@ppReqUser = User.get(ppReqAR.actor)
		@ppReqTime = ppReqAR.event_at
		@ppReqJustif = ppReqAR.details_txt

		erb :test_prov_pass_approve
	end

	post '/tests/:tid/provPassApprove/?' do
		@test = Test.get(params[:tid])
		if(@test.nil?)
			@errstr = "Test not found"
			return erb :error 
		end

		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id))
		halt 401, (erb :unauth) if(!canApproveProvPass?)

		#Create AuditRecord with justification in details
		approvalText = params[:ppApprovalNotes]
		remediation = params[:ppRemediation].to_i
		remediation = 1 if(remediation < 1 || remediation > 3)

		confirm = false
		if(params[:confirm].downcase == "confirm")
			confirm = true
		end
		if(!confirm)
			redirect "/tests/#{@test.id}"
			return
		end

		vrloActions = false
		if (!params[:vrloActions].nil?)
			vrloActions = true
		end

		#Create audit record
		ar = AuditRecord.create(:event_type => EVENT_TYPE::PROV_PASS_APPROVE, :event_at => DateTime.now, :actor => @session[:uid], :details_txt => approvalText, 
								:target_a_type => LINK_TYPE::TEST, :target_a => @test.id, :target_b_type => LINK_TYPE::APPLICATION, :target_b => @app.id)

		if(!ar.saved?)
			Rollbar.error("Error saving AuditRecord object", {:where => "prov pass approval", :whatId => @test.id, :fault => ar.errors.to_s})
			@errstr = "Error approving provisional pass (AuditRecord creation error)"
			erb :error
		end

		#set test. complete  pass  provPassReq  provPass
		#set test.provPassApprover to UID
		@test.pass = true
		@test.provPass = true
		@test.provPassApprover = @session[:uid]
		@test.provPassExpiry = Date.today >> remediation
		if(!@test.save)
			Rollbar.error("Error saving Test object", {:where => "prov pass approval", :fault => @test.errors.to_s})
			@errstr = "Error approving provisional pass (Test record save error)"
			erb :error
		end

		#Notify requestor of approval
		ppReqAR = AuditRecord.last(:event_type => EVENT_TYPE::PROV_PASS_REQUEST, :target_a => @test.id)
		Notification.create(:uidToNotify => ppReqAR.actor, :what => LINK_TYPE::TEST, :whatId => @test.id, :notifClass => NOTIF_CLASS::PROV_PASS_APPROVE)
		
		#Perform all normal test pass actions (test.closed, closed time, snapshots, send email, update record (using new provpass function), etc.)
		@test.complete = true
		@test.closed_at = Time.now
		@test.approved_by = @session[:uid] #This is the contractor approved_by field
		@test.save

		if(@app.recordType.isLinked && @app.isLinked? && vrloActions)
			vrlo = @app.getVRLO
			begin
				vrloResult = vrlo.doProvPassActions(@app, @test, @session[:uid])
			rescue Exception => e
				Rollbar.error(e, "Unable to perform VRLO Provisional Pass Actions", {:vrlo_key => vrlo.vrlo_key, :aid => @app.id, :vrlo_eid => @app.linkId})
				vrloResult = {:success => false, :errstr => "Exception while performing Linked Object actions"}
			end

			if(!vrloResult[:success])
				session[:errmsg] = "<b>Error:</b> Error performing linked object actions - #{vrloResult[:errstr]}"
			end

			if(!vrloResult[:alerts].nil?)
				session[:vrloAlerts] = vrloResult[:alerts]
			end
		end

		#redirect to test page with new status and test page shows info in header notif
		redirect "/tests/#{@test.id}"
	end

	get '/tests/:tid/report/?' do
		@test = Test.get(params[:tid])
		if(@test.nil?)
			@errstr = "Test not found"
			return erb :error 
		end

		halt 401, (erb :unauth) if(!canViewReview?(@test.application.id))

		attachment "Security Report for #{@test.application.name}.html"
		report_html @test.id
	end

	get '/tests/:tid/viewreport/?' do
		@test = Test.get(params[:tid])
		if(@test.nil?)
			@errstr = "Test not found"
			return erb :error 
		end

		halt 401, (erb :unauth) if(!canViewReview?(@test.application.id))

		return report_html @test.id
	end

	get '/tests/:tid/reportpdf/?' do
		@test = Test.get(params[:tid])
		if(@test.nil?)
			@errstr = "Test not found"
			return erb :error 
		end

		halt 401, (erb :unauth) if(!canViewReview?(@test.application.id))

		html = report_html(@test.id)
		kit = PDFKit.new(html, :margin_top => '0in', :margin_right => '0in', :margin_bottom => '0in', :margin_left => '0in')

		attachment "Security Report for #{@test.application.name}.pdf"
		kit.to_pdf
	end

	get '/tests/:tid/delete/?' do
		@test = Test.get(params[:tid])
		if(@test.nil?)
			@errstr = "Test not found"
			return erb :error 
		end

		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id))
		halt 401, (erb :unauth) if(!canDeleteTest?(@test.id))

		erb :test_confirm_delete
	end

	post '/tests/:tid/delete/?' do
		@test = Test.get(params[:tid])
		if(@test.nil?)
			@errstr = "Test not found"
			return erb :error 
		end
		halt 401, (erb :unauth) if(!canViewReview?(@test.application.id))
		halt 401, (erb :unauth) if(!canDeleteTest?(@test.id))

		redirId = @test.application.id

		confirm = false
		if(params[:confirm].downcase == "confirm")
			confirm = true
		end

		if(!confirm)
			redirect "/tests/#{@test.id}"
			return
		else
			@test.vulnerabilities.each do |v|
				v.sections.each do |s|
					s.destroy!
				end
				v.destroy!
			end
			logAudit(EVENT_TYPE::TEST_DELETE, LINK_TYPE::TEST, @test.id)
			@test.destroy!
			redirect "/reviews/#{redirId}"
		end
	end

	get '/tests/:tid/viewTypes/?' do
		@test = Test.get(params[:tid])

		if(@test.nil? || !canViewReview?(@test.application.id))
			@errstr = "Cannot access test"
			erb :error
		end

		@app = @test.application
		@vulnTypes = VulnType.getByRecordType(@app.record_type).sort{ |x,y| x.getLabel <=> y.getLabel}
		appFlagIds = @app.flags.map{|f| f.id}
		@vulnTypes.delete_if do |vt|
			if(!vt.requiredFlags.nil? && !vt.requiredFlags.empty?)
				delVt = true
				vt.requiredFlags.each do |fid|
					if(appFlagIds.include?(fid))
						delVt = false
					end
				end

				if(delVt)
					true
				end
			end
		end

		erb :test_preview_vts
	end

	get '/tests/:tid/:vid/?' do
		@vuln = Vulnerability.get(params[:vid])
		if(@vuln.nil?)
			@errstr = "Vuln not found"
			return erb :error 
		end
		@test = @vuln.test
		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		@vsOptions = VulnSource.all(:enabled => true)

		@comments = Comment.commentsForVuln(@vuln.id, @session[:uid], @session[:org])
		@unreadComments = 0
		@comments.each do |c|
			@unreadComments += 1 if(c.isUnseen?(session[:uid]))
		end

		if(!params[:fromNotif].nil?)
			@fromNotif = true
		end

		if(!@session[:errmsg].nil? && !@session[:errmsg].empty?)
			@error = @session[:errmsg]
			@session[:errmsg] = nil
		end

		if(@vuln.vulntype == 0)
			@enabledSections = nil
		else
			@enabledSections = @vuln.vtobj.enabledSections
		end

		@pageTitle = @app.name + " - " + @test.name

		erb :vuln_single
	end

	post '/tests/:tid/:vid/updateCwe/?' do
		@vuln = Vulnerability.get(params[:vid])
		if(@vuln.nil?)
			@errstr = "Vuln not found"
			return erb :error 
		end

		@test = @vuln.test
		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		newCwe = params[:cweOverride].to_i
		if(!newCwe.nil? && newCwe > 0)
			@vuln.cweOverride = newCwe
		else
			@vuln.cweOverride = nil
		end

		@vuln.save

		redirect "/tests/#{@test.id}/#{@vuln.id}"
	end

	get '/tests/:tid/:vid/source/:vsid/?' do
		@vuln = Vulnerability.get(params[:vid])
		if(@vuln.nil?)
			@errstr = "Vuln not found"
			return erb :error 
		end
		@test = @vuln.test
		halt 401, (erb :unauth) if(!canViewReview?(@test.application.id))

		vsid = params[:vsid].to_i
		if(vsid == 0 || !VulnSource.get(vsid).nil?)
			@vuln.vulnSource = vsid
			@vuln.save
		end

		redirect "/tests/#{params[:tid]}/#{params[:vid]}"
	end

	post '/tests/:tid/:vid/create/?' do
		@vuln = Vulnerability.get(params[:vid])
		if(@vuln.nil?)
			@errstr = "Vuln not found"
			return erb :error 
		end
		@test = @vuln.test
		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		type = params[:type].to_i
		sectsToCreate = Array.new
		data = params[:data]

		if(type == SECT_TYPE::MULTI)
			sectsToCreate << {:type => SECT_TYPE::BURP, :data => params[:burp]} if(!params[:burp].nil? && !params[:burp].strip.nil? && !params[:burp].strip.empty?)
			sectsToCreate << {:type => SECT_TYPE::URL, :data => params[:url]} if(!params[:url].nil? && !params[:url].strip.nil? && !params[:url].strip.empty?)
			sectsToCreate << {:type => SECT_TYPE::FILE, :data => params[:file]} if(!params[:file].nil? && !params[:file].strip.nil? && !params[:file].strip.empty?)
			sectsToCreate << {:type => SECT_TYPE::SSHOT, :data => params[:sshot]} if(!params[:sshot].nil?)
			sectsToCreate << {:type => SECT_TYPE::OUTPUT, :data => params[:output]} if(!params[:output].nil? && !params[:output].strip.nil? && !params[:output].strip.empty?)
			sectsToCreate << {:type => SECT_TYPE::CODE, :data => params[:code]} if(!params[:code].nil? && !params[:code].strip.nil? && !params[:code].strip.empty?)
			sectsToCreate << {:type => SECT_TYPE::NOTES, :data => params[:notes]} if(!params[:notes].nil? && !params[:notes].strip.nil? && !params[:notes].strip.empty?)
			sectsToCreate << {:type => SECT_TYPE::PAYLOAD, :data => params[:payload]} if(!params[:sshot].nil?)
		elsif(type < 0 || type > 10)
			@session[:errmsg] = "Invalid Section Type"
			redirect "/tests/#{params[:tid]}/#{params[:vid]}"
		else
			sectsToCreate << {:type => type, :data => data}
		end

		sectsToCreate.each do |sect|
			type = sect[:type]
			data = sect[:data]

			if((type != SECT_TYPE::SSHOT && type != SECT_TYPE::PAYLOAD) && (data.strip.nil? || data.strip.empty?))
				@session[:errmsg] = "Invalid Section Data"
				next
			end

			if(type == SECT_TYPE::SSHOT)
				if(data.nil?)
					@session[:errmsg] = "Invalid Section Data"
					next
				end

				#check size against limit
				sshotSizeLimit = getSetting("SSHOT_MAX_SIZE_KB")
				sshotSizeLimit = (sshotSizeLimit.nil?) ? 1024 : sshotSizeLimit.to_i
				size = (File.size(data[:tempfile]).to_f)/1024

				if(size > sshotSizeLimit)
					@session[:errmsg] = "Image file too large (Max #{sshotSizeLimit} KB)"
					next
				end

				file = File.open(data[:tempfile], "rb")
				filename = data[:filename].to_s
				contents = file.read
				data = Base64.encode64(contents)
				@vuln.sections.new(:type => type, :body => data, :fname => filename, :listOrder => @vuln.sections.count)
			elsif(type == SECT_TYPE::PAYLOAD)
				if(data.nil?)
					@session[:errmsg] = "Invalid Section Data"
					next
				end

				#check size against limit
				payloadSizeLimit = getSetting("PAYLOAD_MAX_SIZE_KB")
				payloadSizeLimit = (payloadSizeLimit.nil?) ? 1024 : payloadSizeLimit.to_i
				size = (File.size(data[:tempfile]).to_f)/1024

				if(size > payloadSizeLimit)
					@session[:errmsg] = "Payload file too large (Max #{payloadSizeLimit} KB)"
					next
				end

				file = File.open(data[:tempfile], "rb")
				filename = data[:filename].to_s
				contents = file.read
				data = Base64.encode64(contents)
				@vuln.sections.new(:type => type, :body => data, :fname => filename, :listOrder => @vuln.sections.count)
			elsif(type == SECT_TYPE::BURP)
				result = data.scan(/<~=~=~=~=~=~=~=StartVulnReport:(.+?)=~=~=~=~=~=~=~>(.+?)<~=~=~=~=~=~=~=EndVulnReport:\1=~=~=~=~=~=~=~>/mi)
				result.each do |res|
					case res[0].downcase 
						when "url"
							@vuln.sections.create(:type => SECT_TYPE::URL, :body => res[1], :listOrder => @vuln.sections.count)
						when "request"
							@vuln.sections.create(:type => SECT_TYPE::CODE, :body => Base64.decode64(res[1]), :listOrder => @vuln.sections.count)
						when "response"
							@vuln.sections.create(:type => SECT_TYPE::OUTPUT, :body => Base64.decode64(res[1]), :listOrder => @vuln.sections.count)
						else
							@vuln.sections.create(:type => SECT_TYPE::NOTES, :body => res[1], :listOrder => @vuln.sections.count)
						end
				end
			else
				@vuln.sections.new(:type => type, :body => data.strip, :listOrder => @vuln.sections.count)
			end

			@vuln.save
		end

		redirect "/tests/#{params[:tid]}/#{params[:vid]}"
	end

	get '/tests/:tid/:vid/unverify?' do
		@vuln = Vulnerability.get(params[:vid])
		if(@vuln.nil?)
			@errstr = "Vuln not found"
			return erb :error 
		end
		@test = @vuln.test
		halt 401, (erb :unauth) if(!canViewReview?(@test.application.id))

		@vuln.verified = false
		@vuln.falsepos = false
		@vuln.save

		redirect "/tests/#{params[:tid]}/#{params[:vid]}"
	end

	get '/tests/:tid/:vid/fp?' do
		@vuln = Vulnerability.get(params[:vid])
		if(@vuln.nil?)
			@errstr = "Vuln not found"
			return erb :error 
		end
		@test = @vuln.test
		halt 401, (erb :unauth) if(!canViewReview?(@test.application.id))

		@vuln.verified = true
		@vuln.falsepos = true
		@vuln.save

		redirect "/tests/#{params[:tid]}/#{params[:vid]}"
	end

	get '/tests/:tid/:vid/verify?' do
		@vuln = Vulnerability.get(params[:vid])
		if(@vuln.nil?)
			@errstr = "Vuln not found"
			return erb :error 
		end
		@test = @vuln.test
		halt 401, (erb :unauth) if(!canViewReview?(@test.application.id))

		@vuln.verified = true
		@vuln.falsepos = false
		@vuln.save

		redirect "/tests/#{params[:tid]}/#{params[:vid]}"
	end

	post '/tests/:tid/:vid/star/?' do
		@vuln = Vulnerability.get(params[:vid])
		return 404 if(@vuln.nil?)

		@test = @vuln.test
		return 401 if(!canViewReview?(@test.application.id))

		@vuln.starred = true
		@vuln.save
		return 200
	end

	post '/tests/:tid/:vid/unstar/?' do
		@vuln = Vulnerability.get(params[:vid])
		return 404 if(@vuln.nil?)

		@test = @vuln.test
		return 401 if(!canViewReview?(@test.application.id))

		@vuln.starred = false
		@vuln.save
		return 200
	end

	get '/tests/:tid/:vid/priority/:pri/?' do
		@vuln = Vulnerability.get(params[:vid])
		if(@vuln.nil?)
			@errstr = "Vuln not found"
			return erb :error 
		end
		@test = @vuln.test
		halt 401, (erb :unauth) if(!canViewReview?(@test.application.id))

		newPri = params[:pri].to_i

		if(@vuln.vulntype == 0)
			@vuln.priorityOverride = newPri
		else
			if(newPri != VulnType.get(@vuln.vulntype).priority)
				@vuln.priorityOverride = newPri
			else
				@vuln.priorityOverride = nil
			end
		end

		@vuln.save

		redirect "/tests/#{params[:tid]}/#{params[:vid]}"
	end

	post '/tests/:tid/:vid/reorder?' do
		@vuln = Vulnerability.get(params[:vid])
		if(@vuln.nil?)
			@errstr = "Vuln not found"
			return erb :error 
		end
		@test = @vuln.test
		halt 401, (erb :unauth) if(!canViewReview?(@test.application.id))

		order = params[:order]

		order.each_with_index do |sid, idx|
			s = Section.get(sid)
			s.listOrder = idx
			s.save
		end

		return 200
	end

	get '/tests/:tid/:vid/edit/?' do
		@vuln = Vulnerability.get(params[:vid])
		if(@vuln.nil?)
			@errstr = "Vuln not found"
			return erb :error 
		end

		@test = @vuln.test
		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		@vulnTypes = VulnType.getByRecordType(@app.record_type).sort{ |x,y| x.getLabel <=> y.getLabel}

		erb :vuln_edit
	end

	post '/tests/:tid/:vid/edit/?' do
		@vuln = Vulnerability.get(params[:vid])
		if(@vuln.nil?)
			@errstr = "Vuln not found"
			return erb :error 
		end

		@test = @vuln.test
		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		newType = params[:vulnType].to_i
		if(newType == 0)
			newCustomType = params[:customTypeName].strip
			if(newCustomType == "")
				redirect "/tests/#{@test.id}/#{@vuln.id}/edit"
			end
			@vuln.custom = newCustomType
		else
			@vuln.custom = nil
		end

		@vuln.vulntype = newType
		@vuln.save

		redirect "/tests/#{@test.id}/#{@vuln.id}"
	end

	get '/tests/:tid/:vid/delete/?' do
		@vuln = Vulnerability.get(params[:vid])
		if(@vuln.nil?)
			@errstr = "Vuln not found"
			return erb :error 
		end

		@test = @vuln.test
		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		erb :vuln_confirm_delete
	end

	post '/tests/:tid/:vid/delete/?' do
		@vuln = Vulnerability.get(params[:vid])
		if(@vuln.nil?)
			@errstr = "Vuln not found"
			return erb :error 
		end

		halt 401, (erb :unauth) if(!canViewReview?(@vuln.test.application.id))
		redirTest = @vuln.test

		confirm = false
		if(params[:confirm].downcase == "confirm")
			confirm = true
		end

		if(!confirm)
			redirect "/tests/#{redirTest.id}"
			return
		else
			@vuln.sections.each do |s|
				s.destroy!
			end
			@vuln.destroy!

			if(!params[:ajax].nil?)
				return 200
			else
				redirect "/tests/#{redirTest.id}"
			end
		end
	end

	get '/tests/:tid/:vid/:sid/download/?' do
		@sect = Section.get(params[:sid])
		if(@sect.nil?)
			@errstr = "Section not found"
			return erb :error 
		end

		if(@sect.type != SECT_TYPE::PAYLOAD && @sect.type != SECT_TYPE::SSHOT)
			@errstr = "Can't download this section"
			return erb :error
		end

		fileData = Base64.decode64(@sect.body)

		attachment (@sect.fname.nil?) ? @sect.type_str : @sect.fname
		return fileData
	end

	get '/tests/:tid/:vid/:sid/delete/?' do
		@sect = Section.get(params[:sid])
		if(@sect.nil?)
			@errstr = "Section not found"
			return erb :error 
		end

		@vuln = @sect.vulnerability
		@test = @vuln.test
		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		erb :vuln_sect_confirm_delete
	end

	post '/tests/:tid/:vid/:sid/delete/?' do
		@sect = Section.get(params[:sid])
		if(@sect.nil?)
			@errstr = "Section not found"
			return erb :error 
		end

		redirVuln = @sect.vulnerability
		redirTest = redirVuln.test

		confirm = false
		if(params[:confirm].downcase == "confirm")
			confirm = true
		end

		if(!confirm)
			if(params[:ajax])
				return 500
			end
			redirect "/tests/#{redirTest.id}/#{redirVuln.id}"
		else
			@sect.destroy!
			if(params[:ajax])
				return 200
			end
			redirect "/tests/#{redirTest.id}/#{redirVuln.id}"
		end
	end

	post '/tests/:tid/:vid/:sid/edit/?' do
		@sect = Section.get(params[:sid])
		if(@sect.nil?)
			@errstr = "Section not found"
			return erb :error 
		end

		redirVuln = @sect.vulnerability
		redirTest = redirVuln.test

		newBody = params[:newBody].strip#.gsub(/\r/, '\n')

		@sect.body = newBody
		@sect.save

		redirect "/tests/#{redirTest.id}/#{redirVuln.id}"
	end

	post '/tests/:tid/:vid/:sid/toggleVis/?' do
		sect = Section.get(params[:sid])
		if(sect.nil?)
			return 404
		end

		sect.show = !sect.show
		if(sect.save)
			return {:visible => sect.show}.to_json
		else
			return 500
		end
	end

	get '/tests/doClipboard/test/:tid/?' do
		@test = Test.get(params[:tid])
		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		if(!@session[:clipboard].nil? && @session[:clipboard][:type] == LINK_TYPE::TEST && @session[:clipboard][:id] == @test.id)
			@session[:clipboard] = nil
			return 204
		else
			@session[:clipboard] = {:type => LINK_TYPE::TEST, :id => @test.id}
			return 201
		end
	end

	get '/tests/doClipboard/vuln/:vid/?' do
		@vuln = Vulnerability.get(params[:vid])
		@test = @vuln.test
		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		if(!@session[:clipboard].nil? && @session[:clipboard][:type] == LINK_TYPE::VULN && @session[:clipboard][:id] == @vuln.id)
			@session[:clipboard] = nil
			return 204
		else
			@session[:clipboard] = {:type => LINK_TYPE::VULN, :id => @vuln.id}
			return 201
		end
	end

	get '/tests/doClipboard/pasteToTest/:tid/?' do
		@test = Test.get(params[:tid])
		@app = @test.application
		halt 401, (erb :unauth) if(!canViewReview?(@app.id))

		if(@session[:clipboard].nil?)
			redirect "/tests/#{@test.id}"
		else
			if(@session[:clipboard][:type] == LINK_TYPE::VULN)
				vulnToCopy = Vulnerability.get(@session[:clipboard][:id])
				vulnToCopyAttribs = vulnToCopy.attributes
				vulnToCopyAttribs.delete(:id)
				
				newVuln = @test.vulnerabilities.create(vulnToCopyAttribs)

				vulnToCopy.sections.each do |s|
					sa = s.attributes
					sa.delete(:id)
					newVuln.sections.create(sa)
				end
			elsif(@session[:clipboard][:type] == LINK_TYPE::TEST)
				testToCopy = Test.get(@session[:clipboard][:id])

				testToCopy.vulnerabilities.each do |v|
					va = v.attributes
					va.delete(:id)
					
					newVuln = @test.vulnerabilities.create(va)

					v.sections.each do |s|
						sa = s.attributes
						sa.delete(:id)
						newVuln.sections.create(sa)
					end
				end
			end

			@session[:clipboard] = nil
			redirect "/tests/#{@test.id}"
		end
	end

	get '/vulns/starredVulns/?' do
		@vulns = Vulnerability.all(:starred => true, :order => [:id.desc])

		erb :vuln_starred_list
	end
end