##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

##
# Handle all Vulnreport authentication and permission functions.
module VulnreportAuth
	##
	# Check a given IP address against IP Access Restriction rules to determine if access should be allowed
	# @param request_ip [String] IP address to check access for
	# @param ip_allow [String] String of comma-separated access rules (single IPs, CIDRs, and IP ranges)
	# @return [Boolean] True if access should be allowed for request_ip, false otherwise
	def requestIPAllowed?(request_ip, ip_allow)
		if(!ip_allow.nil?)
			request_ip = IPAddr.new(request.ip)
			ip_allow_result = false

			ip_allow_arr = ip_allow.split(",")

			ip_allow_arr.each do |ip|
				if(ip.include?("/"))
					#CIDR case
					begin
						cidr = IPAddr.new(ip)
					rescue Exception => e
						#bad ip, do nothing
						logputs "CIDR - IP Parse error for #{ip.inspect}. Skipping check!"
						Rollbar.error(e, "CIDR - IP Parse error", {:cidr => ip})
					end

					if(cidr.include?(request_ip))
						ip_allow_result = true
						break
					end
				elsif(ip.include?("-"))
					#Range case
					begin
						ips = ip.split("-")
						low = IPAddr.new(ips[0])
						high = IPAddr.new(ips[1])
					rescue Exception => e
						logputs "IP Range - IP Parse error for #{ip.inspect}. Skipping check!"
						Rollbar.error(e, "IP Range - IP Parse error", {:range => ip})
					end

					if((low..high).include?(request_ip))
						ip_allow_result = true
						break
					end
				else
					#Single IP case
					begin
						ip_addr = IPAddr.new(ip)
					rescue Exception => e
						#bad ip, do nothing
						logputs "Single IP - IP Parse error for #{ip.inspect}. Skipping check!"
						Rollbar.error(e, "Single IP - IP Parse error", {:ip => ip})
					end

					if(ip_addr.eql?(request_ip))
						ip_allow_result = true
						break
					end
				end
			end

			return ip_allow_result
		else
			return true
		end
	end
	
	##
	# Checks if active session is a logged in user
	# @return [Boolean] True if active user is logged in, false otherwise
	def authorized?
		if(session[:org].nil?)
			session[:logged_in] = false;
			session[:username] = nil;
		end
		
		return session[:logged_in] == true && !session[:username].nil?
	end

	##
	# Checks if active session is an admin
	# @return [Boolean] True if active user is an admin, false otherwise
	def admin?
		u = User.get(session[:uid])
		return false if u.org == 0
		return false if !u.active

		return u.admin
	end

	##
	# Checks if active session is a user belonging to a Super org
	# @return [Boolean] True if active user is super, false otherwise
	def super?
		u = User.get(session[:uid])
		return false if !u.verified?
		return false if !u.active
		return true if u.admin
		
		o = Organization.get(u.org)
		return true if o.super
	end

	##
	# Checks if active session is a reports-only user
	# @return [Boolean] True if active user is reports-only, false otherwise
	def reports_only?
		u = User.get(session[:uid])
		return false if !u.active
		return u.reportsOnly
	end

	##
	# Checks if active session is a contractor
	# @return [Boolean] True if active user is a contractor, false otherwise
	def contractor?
		o = Organization.get(session[:org])
		return false if o.nil?
		return o.contractor
	end

	##
	# Requires a user be logged in to view page. Otherwise, redirect to login.
	def protected!
		unless authorized?
			session[:loginredir] = request.path unless (!request.path.nil? && request.path.include?("favicon"))
			redirect "/login"
		end

		u = User.get(session[:uid])
		if(!u.active)
			Rollbar.info("Inactive account access attempt blocked", {:uid => u.id, :username => u.sso_user})
			session[:login_error] = "Your user account is inactive. Please contact your Vulnreport admin."
			redirect "/login"
		end

		if(session[:org] == 0)
			if(u.org != 0)
				session[:org] = u.org
			end
		end
	end

	##
	# Prevent contractors from viewing a page. 
	# If the active user is a contractor, redirect to Unauth page.
	# @viewfile views/unauth.erb
	def no_contractors!
		protected!

		if contractor?
			halt 401, (erb :unauth)
		end
	end

	##
	# Prevent reports_only users from viewing a page. 
	# If the active user is a reports unly user, redirect to Unauth page.
	# @viewfile views/unauth.erb
	def no_reporters!
		protected!

		if reports_only?
			halt 401, (erb :unauth)
		end
	end

	##
	# Allow only admins to see a page.
	# If the active user is not an admin, redirect to Unauth page.
	# @viewfile views/unauth.erb
	def only_admins!
		protected!

		unless admin?
			halt 401, (erb :unauth)
		end
	end

	##
	# Allow only super users (users belonging to a super org) to see a page.
	# If the active user is not a super, redirect to Unauth page.
	# @viewfile views/unauth.erb
	def only_super!
		protected!

		unless (admin? || super?)
			halt 401, (erb :unauth)
		end
	end

	##
	# @deprecated
	# Allow only super users or reports users to see a page.
	# If the active user is not a super or reports_only user, redirect to Unauth page.
	# Good for reports that would otherwise be super, but can be shown to just reports users too.
	# @viewfile views/unauth.erb
	def only_super_or_reporters!
		protected!

		unless (admin? || super? || reports_only?)
			halt 401, (erb :unauth)
		end
	end

	##
	# Block users without an org assigned.
	# If the active user is not assigned an org, redirect to Unauth page.
	# @viewfile views/unauth.erb
	def only_verified!
		protected!

		u = User.get(session[:uid])
		if !u.verified?
			halt 401, (erb :unauth)
		end
	end

	##
	# Check if the given RecordType is accessible to the given Org
	# @param oid [Integer] ID of the Org to check permissions for
	# @param rtid [Integer] ID of the RecordType to check permission to
	# @return [Boolean] True if Org can access the RecordType, false otherwise
	def orgAllowedRT?(oid, rtid)
		return false if(oid.nil? || rtid.nil?)

		l = Link.first(:fromType => LINK_TYPE::ORGANIZATION, :fromId => oid, :toType => LINK_TYPE::ALLOW_APP_RT, :toId => rtid)
		return (!l.nil?)
	end

	##
	# Create a link assigning the given RT as accessible to the given Org
	# @param oid [Integer] ID of the Org
	# @param rtid [Integer] ID of the RecordType to allow
	# @return [Boolean] True if successful, false otherwise
	def allowRTForOrg(oid, rtid)
		return false if(oid.nil? || rtid.nil?)

		l = Link.first(:fromType => LINK_TYPE::ORGANIZATION, :fromId => oid, :toType => LINK_TYPE::ALLOW_APP_RT, :toId => rtid)
		if(!l.nil?)
			return true
		else
			l = Link.create(:fromType => LINK_TYPE::ORGANIZATION, :fromId => oid, :toType => LINK_TYPE::ALLOW_APP_RT, :toId => rtid)
			if(l.saved?)
				return true
			else
				return false
			end
		end
	end

	##
	# Remove link, blocking the given RT from the given Org
	# @param oid [Integer] ID of the Org
	# @param rtid [Integer] ID of the RecordType to remove
	# @return [Boolean] True if successful, false otherwise
	def removeRTForOrg(oid, rtid)
		return false if(oid.nil? || rtid.nil?)

		ls = Link.all(:fromType => LINK_TYPE::ORGANIZATION, :fromId => oid, :toType => LINK_TYPE::ALLOW_APP_RT, :toId => rtid)
		if(ls.nil?)
			return true
		else
			return ls.destroy
		end
	end

	##
	# Get all RecordType IDs accessible for the given Org
	# @param oid [Integer] ID of the Org
	# @return [Array<Integer>] Array of {RecordType} IDs representing the RecordTypes the given Org can access
	def getAllowedRTsForOrg(oid)
		return [] if(oid.nil?)
		allowed = Array.new

		ls = Link.all(:fromType => LINK_TYPE::ORGANIZATION, :fromId => oid, :toType => LINK_TYPE::ALLOW_APP_RT)
		if(!ls.nil?)
			ls.each do |l|
				allowed << l.toId.to_i
			end
		end

		return allowed
	end

	##
	# Get IDs of all Orgs that can access a given RecordType
	# @param rtid [Integer] ID of the RecordType
	# @return [Array<Integer>] Array of {Organization} IDs representing the orgs that can access the given RecordType
	def getOrgsAllowedForRT(rtid)
		return [] if(rtid.nil?)
		allowed = Array.new

		ls = Link.all(:fromType => LINK_TYPE::ORGANIZATION, :toType => LINK_TYPE::ALLOW_APP_RT, :toId => rtid)
		if(!ls.nil?)
			ls.each do |l|
				allowed << l.fromId.to_i
			end
		end

		return allowed
	end

	##
	# Get all RecordType IDs accessible for the given User
	# @param uid [Integer] ID of the User
	# @return [Array<Integer>] Array of {RecordType} IDs representing the RecordTypes the given User can access
	def getAllowedRTsForUser(uid)
		return [] if(uid.nil?)
		allowed = Array.new

		u = User.get(uid)
		return [] if (u.nil? || !u.active)

		o = Organization.get(u.org)
		return [] if (o.nil?)

		if(u.admin || o.super)
			return RecordType.allAppRecordTypes().map{|rt| rt.id}
		else
			return getAllowedRTsForOrg(o.id)
		end
	end

	##
	# Get all {RecordType}s accessible for the given User, returning an array of the objects
	# @param uid [Integer] ID of the User
	# @return [Array<RecordType>] Array of {RecordType}s representing the RecordTypes the given User can access
	def getAllowedRTObjsForUser(uid)
		return RecordType.all(:id => getAllowedRTsForUser(uid))
	end

	##
	# Check a list of {RecordType} IDs against those given {User} is allowed to access and return only those the User is allowed to access
	# @param requested [Array<Integer>] Array of integers representing {RecordType} IDs User wants to access
	# @param uid [Integer] ID of the User
	# @return [Array<Integer>] Array of integers representing {RecordType} ID's from requested array User can access
	def checkRecordTypeListForAccess(requested, uid)
		if(requested.nil? || requested.kind_of?(Array) || requested.size == 0)
			return []
		end
		
		return (requested & (getAllowedRTsForUser(uid)))
	end

	##
	# Check if a User is on the allowed UID list for an Application
	# @param uid [Inteder] {User} ID to check access for
	# @param aid [Integer] {Application} ID to check access against
	# @return [Boolean] True if user is in the allow list
	def userAllowedForApp(uid, aid)
		a = Application.get(aid)
		return false if a.nil?

		return (!a.allow_UIDs.nil? && a.allow_UIDs.include?(uid))
	end

	##
	# Remember (for 30 mins) that a user has been warned about a private app they are viewing.
	# Done in Redis so we can auto-expire warning. Audit event is logged.
	# @param uid [Inteder] {User} ID
	# @param aid [Integer] {Application} ID
	# @return [Boolean] True if successful
	def markUserWarnedApp(uid, aid, sec=1800)
		thisAr = AuditRecord.create(:event_type => EVENT_TYPE::ADMIN_OVERRIDE_PRIVATE_APP, :event_at => DateTime.now, :actor => @session[:uid], :target_a_type => LINK_TYPE::APPLICATION, :target_a => aid.to_s) 
		return settings.redis.setex("privatewarn_u_#{uid.to_s}_a_#{aid.to_s}", sec, "true")
	end

	##
	# Remember (for 30 mins) that a user has been warned about a private test they are viewing.
	# Done in Redis so we can auto-expire warning. Audit event is logged.
	# @param uid [Inteder] {User} ID
	# @param tid [Integer] {Test} ID
	# @return [Boolean] True if successful
	def markUserWarnedTest(uid, tid, sec=1800)
		thisAr = AuditRecord.create(:event_type => EVENT_TYPE::ADMIN_OVERRIDE_PRIVATE_TEST, :event_at => DateTime.now, :actor => @session[:uid], :target_a_type => LINK_TYPE::TEST, :target_a => tid.to_s) 
		return settings.redis.setex("privatewarn_u_#{uid.to_s}_t_#{tid.to_s}", sec, "true")
	end

	##
	# Check if a user has been recently warned about viewing a private app
	# @param uid [Inteder] {User} ID
	# @param aid [Integer] {Application} ID
	# @return [Boolean] True if they have been warned recently, false otherwise
	def userWarnedForApp?(uid, aid)
		return settings.redis.exists("privatewarn_u_#{uid.to_s}_a_#{aid.to_s}")
	end

	##
	# Check if a user has been recently warned about viewing a private test
	# @param uid [Inteder] {User} ID
	# @param tid [Integer] {Test} ID
	# @return [Boolean] True if they have been warned recently, false otherwise
	def userWarnedForTest?(uid, tid)
		return settings.redis.exists("privatewarn_u_#{uid.to_s}_t_#{tid.to_s}")
	end

	##
	# Check if a user is allowed to view a review
	#     Permissions rules are as follows:
	#     (1) => If user not active NO
	#     (2) => If user is admin YES (warning for private reviews takes place elsewhere)
	#     (3) => If user is on app's UID override list YES
	#         => If test is private
	#         (3) => => If UID on allowed list YES [handled above]
	#         (4) => => Else NO
	#     (5) => If test is marked as global YES
	#     (6) => If user is not assigned to an Org and not yet allowed NO
	#     (7) => If user's org is Super YES
	#     (8) => If user's org is allowed for app's RT YES
	#     (9) => If user is marked as reviewer for any of app's tests YES
	#     (10) => ELSE NO
	# @param aid [Integer] ID of the {Application} to check permission against.
	# @param uid [Integer] ID of the {User} to check permission for. Defaults to logged in user.
	# @return [Boolean] True if user can access the application, false otherwise.
	def canViewReview?(aid, uid=session[:uid])
		u = User.get(uid)
		return false if !u.active #(1)
		return true if u.admin #(2)

		a = Application.get(aid)
		return true if(!a.allow_UIDs.nil? && a.allow_UIDs.include?(u.id)) #(3)

		return false if(a.isPrivate) #(4)
		return true if a.global #(5)
		
		return false if !u.verified? #(6)
		o = Organization.get(u.org)
		return true if o.super #(7)
		
		allowedOrgs = getOrgsAllowedForRT(a.record_type)
		return true if(allowedOrgs.include?(o.id)) #(8)

		a.tests.each do |t|
			return true if t.reviewer == u.id #(9)
		end

		return false #(10)
	end

	##
	# Check if the logged in user is allowed to finalize (pass, fail, or request prov pass) a given {Test}.
	# To finalize a test, user must be able to access the review the test is on. If they require approval, that
	# step will be taken care of in the status update. If a test is in the is_pending state (awaiting approval)
	# this function restricts finalize ability to those who can approve based on the pending_by UID.
	# @param tid [Integer] ID of the Test to check against
	# @return [Boolean] True if user can finalize the test, false otherwise
	def canFinalizeTest?(tid, uid=session[:uid])
		u = User.get(uid)
		return false if !u.active
		return false if !u.verified?
		return true if u.admin

		t = Test.get(tid)
		if(!t.is_pending)
			return canViewReview?(t.application_id)
		else
			pendingUser = User.get(t.pending_by)
			approvers = pendingUser.approvers
			if(!approvers[:users].nil? && approvers[:users].include?(uid))
				return true
			end

			if(!approvers[:orgs].nil? && approvers[:orgs].include?(u.org))
				return true
			end
		end

		return false
	end

	##
	# Check if the logged in user is allowed to delete a {Application}
	# @param aid [Integer] ID of the Application to check against
	# @return [Boolean] True if user can delete the Application, false otherwise
	def canDeleteReview?(aid)
		#Able to delete if: admin, super org, app owner
		u = User.get(session[:uid])
		return false if !u.active
		return true if u.admin
		return false if !u.verified?

		a = Application.get(aid)
		return true if (aid = a.owner)

		o = Organization.get(u.org)
		return true if o.super

		return false
	end

	##
	# Check if the logged in user is allowed to delete a {Test}
	# @param tid [Integer] ID of the Test to check against
	# @return [Boolean] True if user can delete the Test, false otherwise
	def canDeleteTest?(tid)
		#If admin or in super org, yes
		#If created test or in org that created test, yes
		#Else no
		u = User.get(session[:uid])
		return false if !u.active
		return true if u.admin

		return false if !u.verified?
		o = Organization.get(u.org)
		return true if o.super

		t = Test.get(tid)
		return true if (u.id = t.reviewer)
		
		rev = User.get(t.reviewer)
		return true if (u.org == rev.org)

		return false
	end

	##
	# Check if the logged in user has perm to pass a test from given {Application} ID to a contractor.
	# Requires that user have the canPassToCon perm bit and be able to access the RT of given Application ID.
	# @param aid [Integer] ID of the {Application} to check permission against
	# @return [Boolean] True if user is allowed, false otherwise
	def canPassToContractor?(aid)
		u = User.get(session[:uid])
		return false if !u.active
		return true if u.admin

		return false if !u.verified?
		return false if(!u.canPassToCon)
		return false if(!canViewReview?(aid, u.id))
		return true
	end

	##
	# Check if the logged in user has perm to pass a test from an {Application} with given {RecordType} ID to a contractor.
	# Requires that user have the canPassToCon perm bit and be able to access the given RT
	# @param rtid [Integer] ID of the {RecordType} to check permission against
	# @return [Boolean] True if user is allowed, false otherwise
	def canPassRTToContractor?(rtid, uid=session[:uid])
		u = User.get(uid)
		return false if !u.active
		return true if u.admin

		return false if !u.verified?
		return false if(!u.canPassToCon)
		return false if(!(getAllowedRTsForUser(uid).include?(rtid)))
		return true
	end

	##
	# Check if the logged in user has perm to use reporting
	# @return [Boolean] True if user is allowed, false otherwise
	def canUseReports?()
		u = User.get(session[:uid])
		return false if !u.active
		return true if u.admin

		return false if !u.verified?
		return true if reports_only?

		o = Organization.get(u.org)
		return o.canReport
	end

	##
	# Check if the logged in user has perm to audit monitoring alerts
	# @return [Boolean] True if user is allowed, false otherwise
	def canAuditMonitors?()
		u = User.get(session[:uid])
		return false if !u.active
		return true if u.admin
		return false if !u.verified?
		return true if u.canAuditMonitors

		return false
	end

	##
	# Check if the logged in user has perm to approve Provisional Passes
	# @return [Boolean] True if user is allowed, false otherwise
	def canApproveProvPass?()
		u = User.get(session[:uid])
		return false if !u.active
		return true if u.provPassApprover

		return false
	end

	##
	# Check if the logged in user is a manager
	# @return [Boolean] True if user is a manager, false otherwise
	def isManager?()
		u = User.get(session[:uid])
		return u.isManager?
	end

	##
	# Check if the logged in user is the direct manager of the given {User}
	# @param targetUid [Integer] ID of the {User} to check management of
	# @param uid [Integer] ID of the {User} to check perm for
	# @return [Boolean] True if logged in user is direct manager of given user
	def isManagerFor?(targetUid, uid=session[:uid])
		targetUser = User.get(targetUid)
		return false if(targetUser.nil?)

		return (targetUser.manager_id == uid)
	end

	##
	# Check if user is in the management chain of the given {User}
	# @param targetUid [Integer] ID of the {User} to check management of
	# @param uid [Integer] ID of the {User} to check perm for
	# @return [Boolean] True if logged in user is in management chain of given user
	def isInManagementChain?(targetUid, uid=session[:uid])
		targetUser = User.get(targetUid)

		while(!targetUser.nil?)
			if(targetUser.manager_id == uid)
				return true
			else
				targetUser = targetUser.manager
			end
		end

		return false
	end
	
end
