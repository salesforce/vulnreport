##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

##
# Resource representing a Notification to a {User} about a {Comment} they should view or an action they need to take. 
# Notifications are displayed in UI and do not represent email sent by Vulnreport.
class Notification
	include DataMapper::Resource

	property :id,				Serial 							#@return [Integer] Primary Key
	property :uidToNotify,		Integer							#@return [Integer] ID of {User} this Notification applies to
	property :notifClass,		Integer 						#@return [NOTIF_CLASS] Type of Notification
	property :what,				Integer 						#@return [LINK_TYPE] Type of resource this Notification is attached to
	property :whatId,			Integer 						#@return [Integer] ID of resource this Notification is attached to
	property :body,				Text, :length => 2048 			#@return [String] Body/text of this Notification
	property :viewed,			Boolean, :default => false 		#@return [Boolean] True if this Notification has been viewed by User
	property :created_at, 		DateTime 						#@return [DateTime] Date/Time Notification created (DM Handled)
	property :renewed_at,		DateTime 						#@return [DateTime] If a second notification for same what/whatId is logged, set this at that Date/Time
	property :renewed_count,	Integer, :default => 0 			#@return [Integer] Number of times this Notification has been renewed
	property :viewed_at,		DateTime 						#@return [DateTime] Date/Time Notification was viewed by User

	##
	# Before creating the Notification, check if it should instead be a renewal (same UID, What, and WhatID for an Notification not yet viewed).
	# If it should be a renewal, update that existing Notification. Otherwise, create a notification. As part of that, generate the Notification
	# body based on what object it is being attached to and the class of Notification ({NOTIF_CLASS}).
	before :create do
		existing = Notification.first(:uidToNotify => self.uidToNotify, :what => self.what, :whatId => self.whatId, :viewed => false)
		if(!existing.nil?)
			existing.renewed_at = DateTime.now
			existing.renewed_count += 1
			existing.save
			throw :halt
		end

		if(!self.notifClass.nil? && self.body.nil?)
			whatStr = nil
			if(self.what == LINK_TYPE::APPLICATION)
				app = Application.get(self.whatId)
				whatStr = app.name
			elsif(self.what == LINK_TYPE::TEST)
				test = Test.get(self.whatId)
				whatStr = test.name + " - " + test.application.name
			elsif(self.what == LINK_TYPE::VULN)
				vuln = Vulnerability.get(self.whatId)
				whatStr = vuln.type_str + " on " + vuln.test.name + " - " + vuln.test.application.name
			end

			if(self.notifClass == NOTIF_CLASS::REPLY_TO_COMMENT)
				if(!whatStr.nil?)
					self.body = "New reply on '#{whatStr}'"
				else
					self.body = "New reply to comment"
				end
			elsif(self.notifClass == NOTIF_CLASS::COMMENT_APP)
				if(!whatStr.nil?)
					self.body = "New comment on an Application you've tested - '#{whatStr}'"
				else
					self.body = "New comment on an Application you've tested"
				end
			elsif(self.notifClass == NOTIF_CLASS::COMMENT_TEST)
				if(!whatStr.nil?)
					self.body = "New comment on your test - '#{whatStr}'"
				else
					self.body = "New comment on one of your tests"
				end
			elsif(self.notifClass == NOTIF_CLASS::COMMENT_VULN)
				if(!whatStr.nil?)
					self.body = "New comment on a vuln you created - '#{whatStr}'"
				else
					self.body = "New comment on a vuln you created"
				end
			elsif(self.notifClass == NOTIF_CLASS::COMMENT_APP_APPROVER)
				if(!whatStr.nil?)
					self.body = "New comment on an Application you've approved a test for - '#{whatStr}'"
				else
					self.body = "New comment on an Application you've approved a test for"
				end
			elsif(self.notifClass == NOTIF_CLASS::COMMENT_TEST_APPROVER)
				if(!whatStr.nil?)
					self.body = "New comment on a test you approved - '#{whatStr}'"
				else
					self.body = "New comment on a test you approved"
				end
			elsif(self.notifClass == NOTIF_CLASS::COMMENT_VULN_APPROVER)
				if(!whatStr.nil?)
					self.body = "New comment on a vuln for a test you approved - '#{whatStr}'"
				else
					self.body = "New comment on a vuln for a test you approved"
				end
			elsif(self.notifClass == NOTIF_CLASS::PROV_PASS_REQUEST)
				if(!whatStr.nil?)
					self.body = "Provisional pass requested for '#{whatStr}'"
				else
					self.body = "Provisional pass requested"
				end
			elsif(self.notifClass == NOTIF_CLASS::PROV_PASS_APPROVE)
				if(!whatStr.nil?)
					self.body = "Your provisional pass request for '#{whatStr}' has been approved"
				else
					self.body = "Your provisional pass has been approved"
				end
			end
		end
	end

	##
	# Get all unseen Notifications for a {User}
	# @param uid [Integer] ID of {User} to get new Notifications for
	# @return [Array<Notification>] Unseen Notifications for given User
	def self.forUser(uid)
		return all(:uidToNotify => uid, :viewed => false, :order => [:id.desc])
	end

	##
	# Get all Notifications for a {User}
	# @param uid [Integer] ID of {User} to get Notifications for
	# @return [Array<Notification>] All Notifications for given User
	def self.allForUser(uid)
		return all(:uidToNotify => uid, :order => [:id.desc])
	end

	##
	# Mark a Notification as viewed
	# @param nid [Integer] Notification ID
	# @return [Boolean] True if successful, false otherwise
	def self.markRead(nid)
		n = get(nid)
		n.viewed = true
		return n.save
	end

	##
	# Mark all Notifications for a given {User} as viewed
	# @param uid [Integer] User ID
	# @return [Array<Notification>] All Notifications for User that were marked as viewed
	def self.markAllUserRead(uid)
		ns = all(:uidToNotify => uid, :viewed => false)
		ns.update(:viewed => true)
		return ns
	end

	##
	# The HREF for this Notification to link to
	# @return [String] HREF to use in a link for this Notification
	def link
		#Separate these out so they dont get the fromNotif arg that auto-opens comments
		if(self.notifClass == NOTIF_CLASS::PROV_PASS_REQUEST || self.notifClass == NOTIF_CLASS::PROV_PASS_APPROVE)
			return "/reviews/#{self.whatId}" if(self.what == LINK_TYPE::APPLICATION)
			return "/tests/#{self.whatId}" if(self.what == LINK_TYPE::TEST)
		end

		return "/reviews/#{self.whatId}?fromNotif=1" if(self.what == LINK_TYPE::APPLICATION)
		return "/tests/#{self.whatId}?fromNotif=1" if(self.what == LINK_TYPE::TEST)
		if(self.what == LINK_TYPE::VULN)
			v = Vulnerability.get(self.whatId)
			return "" if(v.nil?)
			return "/tests/#{v.test.id}/#{self.whatId}?fromNotif=1"
		end

		return nil
	end
end