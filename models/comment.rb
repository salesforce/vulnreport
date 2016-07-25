##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

##
# Resource to store comments made within Vulnreport and attached to other Vulnreport objects
class Comment
	include DataMapper::Resource

	property :id,			Serial 									#@return [Integer] Primary Key
	property :author,		Integer 								#@return [Integer] ID of author {User}
	property :what,			Integer 								#@return [LINK_TYPE] Type of resource this comment is attached to
	property :whatId,		Integer 								#@return [Integer] ID of resource this comment is attached to
	property :vis_authOrg,	Boolean, :default => true 				#@return [Boolean] True if comment is visible to author {User}'s {Organization}
	property :vis_tester,	Boolean, :default => true 				#@return [Boolean] True if comment is visible to reviewer {User}
	property :vis_testOrg,	Boolean, :default => true 				#@return [Boolean] True if comment is visible to reviewer {User}'s {Organization}
	property :body,			Text, :length => 8192, :lazy => false 	#@return [String] Comment text
	property :views,		Object, :default => [] 					#@return [Array<Integer>] IDs of {User}s who have viewed this Comment
	property :created_at, 	DateTime								#@return [DateTime] Date/Time Comment created (DM Handled)
	property :updated_at, 	DateTime 								#@return [DateTime] Date/Time Comment last updated (DM Handled)

	before :create, :notify

	##
	# Before the Comment is created, create the appropriate {Notification}s so that {User}s are alerted to view the Comment.
	# 
	# If {Application}, notify previous commenters and reviewer for active {Test}s if one/they exist(s). 
	# Notify approvers of those Tests if they were contractor tests.
	#
	# If {Test}, notify previous commenters and approver if Test was a contractor test
	#
	# If {Vulnerability}, notify previous commenters and reviewer of {Test} attached to.
	# Notify approvers of those Tests if they were contractor tests.
	#
	# @return [Void]
	def notify
		toNotify_reply = Array.new
		toNotify_owner = Array.new
		toNotify_approver = Array.new
		comments = nil

		if(self.what == LINK_TYPE::APPLICATION)
			comments = Comment.commentsForApp(self.whatId)
			
			#App has no "owner", so notify tester for active test if one exists
			app = Application.get(self.whatId)
			app.tests.each do |t|
				toNotify_owner << t.reviewer unless toNotify_owner.include?(t.reviewer)

				if(t.contractor_test && !t.approved_by.nil?)
					toNotify_approver << t.approved_by
				end
			end
		elsif(self.what == LINK_TYPE::TEST)
			comments = Comment.commentsForTest(self.whatId)

			#test owner
			test = Test.get(self.whatId)
			toNotify_owner << test.reviewer

			if(test.contractor_test && !test.approved_by.nil? && test.approved_by > 0)
				toNotify_approver << test.approved_by
			end
		elsif(self.what == LINK_TYPE::VULN)
			comments = Comment.commentsForVuln(self.whatId)

			#test owner
			vuln = Vulnerability.get(self.whatId)
			toNotify_owner << vuln.test.reviewer

			if(vuln.test.contractor_test && !vuln.test.approved_by.nil? && vuln.test.approved_by > 0)
				toNotify_approver << vuln.test.approved_by
			end
		end

		comments.each do |c|
			toNotify_reply << c.author unless toNotify_reply.include?(c.author)
		end

		toNotify_owner.each do |u|
			next if toNotify_reply.include?(u)
			next if u == self.author

			if(self.what == LINK_TYPE::APPLICATION)
				Notification.create(:uidToNotify => u, :what => self.what, :whatId => self.whatId, :notifClass => NOTIF_CLASS::COMMENT_APP)
			elsif(self.what == LINK_TYPE::TEST)
				Notification.create(:uidToNotify => u, :what => self.what, :whatId => self.whatId, :notifClass => NOTIF_CLASS::COMMENT_TEST)
			elsif(self.what == LINK_TYPE::VULN)
				Notification.create(:uidToNotify => u, :what => self.what, :whatId => self.whatId, :notifClass => NOTIF_CLASS::COMMENT_VULN)
			end
		end

		toNotify_approver.each do |u|
			next if toNotify_reply.include?(u)
			next if u == self.author

			if(self.what == LINK_TYPE::APPLICATION)
				Notification.create(:uidToNotify => u, :what => self.what, :whatId => self.whatId, :notifClass => NOTIF_CLASS::COMMENT_APP_APPROVER)
			elsif(self.what == LINK_TYPE::TEST)
				Notification.create(:uidToNotify => u, :what => self.what, :whatId => self.whatId, :notifClass => NOTIF_CLASS::COMMENT_TEST_APPROVER)
			elsif(self.what == LINK_TYPE::VULN)
				Notification.create(:uidToNotify => u, :what => self.what, :whatId => self.whatId, :notifClass => NOTIF_CLASS::COMMENT_VULN_APPROVER)
			end
		end

		toNotify_reply.each do |u|
			next if u == self.author
			Notification.create(:uidToNotify => u, :what => self.what, :whatId => self.whatId, :notifClass => NOTIF_CLASS::REPLY_TO_COMMENT)
		end
	end

	##
	# Get all Comments belonging to given {Application}
	# @param aid [Integer] ID of {Application} to get Comments for
	# @param viewer_uid [Intever] ID of {User} to view as (for permissions). If nil, system is getting comments
	# @param viewer_orgid [Intever] ID of {Organization} to view as (for permissions). If nil, system is getting comments
	# @return [Array<Comments>] Comments attached to given {Application}, pruned for viewing permissions as needed
	def self.commentsForApp(aid, viewer_uid=nil, viewer_orgid=nil)
		comments = all(:what => LINK_TYPE::APPLICATION, :whatId => aid, :order => [:id.asc])

		return comments if(viewer_uid.nil? || viewer_orgid.nil?)

		#Prune for perms
		app = Application.get(aid)
		comments = comments.delete_if{|c|
			viewer_user = User.get(viewer_uid)
			if(viewer_user.admin || Organization.get(viewer_user.org).super)
				false
				next
			end

			if(c.author == viewer_uid)
				false
				next
			end
			
			testers = Array.new
			app.tests.each do |t|
				testers << t.reviewer unless testers.include?(t.reviewer)
			end

			if(c.vis_tester && (testers.include?(viewer_uid)))
				false 
				next
			end

			authOrg = User.get(c.author).org
			if(c.vis_authOrg && viewer_orgid == authOrg)
				false
				next
			end

			testerOrgs = Array.new
			testers.each do |tr|
				oid = User.get(tr).org
				testerOrgs << oid unless testerOrgs.include?(oid)
			end
			if(c.vis_testOrg && (testerOrgs.include?(viewer_orgid)))
				false
				next
			end

			true
		}

		return comments
	end
	
	##
	# Get all Comments belonging to given {Test}
	# @param tid [Integer] ID of {Test} to get Comments for
	# @param viewer_uid [Intever] ID of {User} to view as (for permissions). If nil, system is getting comments
	# @param viewer_orgid [Intever] ID of {Organization} to view as (for permissions). If nil, system is getting comments
	# @return [Array<Comments>] Comments attached to given {Test}, pruned for viewing permissions as needed
	def self.commentsForTest(tid, viewer_uid=nil, viewer_orgid=nil)
		comments = all(:what => LINK_TYPE::TEST, :whatId => tid, :order => [:id.asc])

		return comments if(viewer_uid.nil? || viewer_orgid.nil?)

		#Prune for perms
		test = Test.get(tid)
		comments = comments.delete_if{|c|
			viewer_user = User.get(viewer_uid)
			if(viewer_user.admin || Organization.get(viewer_user.org).super)
				false
				next
			end

			if(c.author == viewer_uid)
				false
				next
			end
			
			tester = test.reviewer
			if(c.vis_tester && (tester == viewer_uid))
				false 
				next
			end

			authOrg = User.get(c.author).org
			if(c.vis_authOrg && viewer_orgid == authOrg)
				false
				next
			end

			testerOrg = User.get(tester).org
			if(c.vis_testOrg && viewer_orgid == testerOrg)
				false
				next
			end

			true
		}

		return comments
	end

	##
	# Get all Comments belonging to given {Vulnerability}
	# @param vid [Integer] ID of {Vulnerability} to get Comments for
	# @param viewer_uid [Intever] ID of {User} to view as (for permissions). If nil, system is getting comments
	# @param viewer_orgid [Intever] ID of {Organization} to view as (for permissions). If nil, system is getting comments
	# @return [Array<Comments>] Comments attached to given {Vulnerability}, pruned for viewing permissions as needed
	def self.commentsForVuln(vid, viewer_uid=nil, viewer_orgid=nil)
		comments = all(:what => LINK_TYPE::VULN, :whatId => vid, :order => [:id.asc])

		return comments if(viewer_uid.nil? || viewer_orgid.nil?)

		#Prune for perms
		vuln = Vulnerability.get(vid)
		comments = comments.delete_if{|c|
			viewer_user = User.get(viewer_uid)
			if(viewer_user.admin || Organization.get(viewer_user.org).super)
				false
				next
			end

			if(c.author == viewer_uid)
				false
				next
			end
			
			tester = vuln.test.reviewer
			if(c.vis_tester && (tester == viewer_uid))
				false 
				next
			end

			authOrg = User.get(c.author).org
			if(c.vis_authOrg && viewer_orgid == authOrg)
				false
				next
			end

			testerOrg = User.get(tester).org
			if(c.vis_testOrg && viewer_orgid == testerOrg)
				false
				next
			end

			true
		}

		return comments
	end

	##
	# Check if given {User} has viewed this Comment
	# @param uid [Integer] ID of {User} to check seen state for
	# @return [Boolean] True if given User has viewed Comment
	def isUnseen?(uid)
		return (!self.views.include?(uid))
	end

	##
	# Mark comment as seen by given {User}
	# @param uid [Integer] ID of {User} to mark as having seen Comment
	# @return [Void]
	def markSeen(uid)
		v = Array.new
		self.views.map{|x| v << x}
		if(!v.include?(uid))
			v << uid
		end
		self.views = v
		self.save
	end

	##
	# @return [String] A human-readable/UI string representing view permissions for this Comment
	def visibility_str
		return "Visible to All" if(vis_authOrg && vis_tester && vis_testOrg)
		return "Visible to Only Me" if(!vis_authOrg && !vis_tester && !vis_testOrg)
		
		v = []
		v << "Tester" if(vis_tester)
		v << "Author's Org" if(vis_authOrg)
		v << "Tester's Org" if(vis_testOrg)
		return "Visible to " + v.join(", ")
	end
end