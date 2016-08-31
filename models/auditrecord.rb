##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

##
# Records information about an action that was taken and should be recorded
# Tracks action type, user who took the action, and up to 2 linked objects to the action. Can also store a blob and a detail string.
class AuditRecord
	include DataMapper::Resource
	
	property :id,				Serial 						#@return [Integer] Primary Key

	property :created_at, 		DateTime					#@return [DateTime] Date/Time AuditRecord created (DM Handled)
	property :updated_at, 		DateTime					#@return [DateTime] Date/Time AuditRecord last updated (DM Handled)
	property :event_type,		Integer 					#@return [EVENT_TYPE] Type of AuditRecord
	property :event_at,			DateTime					#@return [DateTime] Date/Time the event triggering audit occurred
	property :actor,			Integer 					#@return [Integer] ID of {User} who caused the event

	property :blob,				Text, :length => 1024*8		#@return [String] JSON Blob containing additional even information
	property :details_txt,		Text, :length => 1024*8 	#@return [String] Text of additional event details

	property :target_a_type,	Integer 					#@return [LINK_TYPE] Type of first linked object relating to this AuditRecord. See AuditRecord Overview.
	property :target_a,			String 						#@return [String] ID of first linked object relating to this AuditRecord. See AuditRecord Overview.
	property :target_b_type,	Integer 					#@return [LINK_TYPE] Type of second linked object relating to this AuditRecord. See AuditRecord Overview.
	property :target_b,			String 						#@return [String] ID of second linked object relating to this AuditRecord. See AuditRecord Overview.

	property :reviewed,			Boolean, :default => false  #@return [Boolean] True if AuditRecord has been reviewed and marked as ok
	property :reviewed_at,		DateTime					#@return [DateTime] Date/Time AuditRecord was reviewed
	property :reviewed_by,		Integer  					#@return [Integer] ID of {User} who reviewed AuditRecord
	property :flagged,			Boolean, :default => false  #@return [Boolean] True if flagged as issue/for further review
	property :review_notes,		Text 						#@deprecated @return [String] Text body of review notes

	def blobObj
		if(!self.blob.nil?)
			return JSON.parse(self.blob, {:symbolize_names => true})
		else
			return nil
		end
	end

	def actorName
		u = User.get(self.actor)
		if(u.nil?)
			return "UNK"
		else
			return u.name
		end
	end

	##
	# Generate a string representing the action this AuditRecord recorded. Strings
	# should not include the actor, just the action done.
	# @return [String] the String representing that event type
	def auditString
		if(!self.blob.nil?)
			blobData = JSON.parse(self.blob, {:symbolize_names => true})
		end

		return case self.event_type
		when EVENT_TYPE::PROV_PASS_REQUEST then "Provisional Pass requested"
		when EVENT_TYPE::PROV_PASS_APPROVE then "Provisional Pass approved"
		when EVENT_TYPE::PROV_PASS_DENY then "Provisional Pass denied"
		when EVENT_TYPE::PROV_PASS_REQCANCEL then "Provisional Pass request cancelled"
		when EVENT_TYPE::ADMIN_OVERRIDE_PRIVATE_APP then "Private app view restrictions overridden"
		when EVENT_TYPE::ADMIN_OVERRIDE_PRIVATE_TEST then "Private test view restrictions overridden"
		when EVENT_TYPE::APP_CREATE then "App created"
		when EVENT_TYPE::APP_RENAME then "App renamed <b>#{Rack::Utils::escape_html(blobData[:fromName])}</b> to <b>#{Rack::Utils::escape_html(blobData[:toName])}</b>"
		when EVENT_TYPE::APP_LINK then "App linked to EID #{Rack::Utils::escape_html(self.target_b)} (#{Rack::Utils::escape_html(self.details_txt)})"
		when EVENT_TYPE::APP_UNLINK then "App unlinked from EID #{Rack::Utils::escape_html(self.target_b)}"
		when EVENT_TYPE::APP_MADE_GLOBAL then "App marked <b>global</b>"
		when EVENT_TYPE::APP_MADE_NOTGLOBAL then "App marked <b>not global</b>"
		when EVENT_TYPE::APP_MADE_PRIVATE then "App marked <b>private</b>"
		when EVENT_TYPE::APP_MADE_NOTPRIVATE then "App marked <b>not private</b>"
		when EVENT_TYPE::APP_RTCHANGE then "Changed app RecordType <b>#{Rack::Utils::escape_html(blobData[:fromName])}</b> to <b>#{Rack::Utils::escape_html(blobData[:toName])}</b>"
		when EVENT_TYPE::APP_GEO_SET then "Set app geo to <b>#{geoToString(blobData[:geoId])}</b>"
		when EVENT_TYPE::APP_DELETE then "App deleted"
		when EVENT_TYPE::APP_FLAG_ADD then "App flagged with <b>#{Rack::Utils::escape_html(blobData[:flagName])}</b>"
		when EVENT_TYPE::APP_FLAG_REM then "App flag <b>#{Rack::Utils::escape_html(blobData[:flagName])}</b> removed"
		when EVENT_TYPE::APP_OWNER_ASSIGN then "App owner set to <b>#{Rack::Utils::escape_html(blobData[:userName])}</b>"
		when EVENT_TYPE::TEST_CREATE then "Test created"
		when EVENT_TYPE::TEST_RENAME then "Test renamed <b>#{Rack::Utils::escape_html(blobData[:fromName])}</b> to <b>#{Rack::Utils::escape_html(blobData[:toName])}</b>"
		when EVENT_TYPE::TEST_REVIEWER_UNASSIGNED then "Reviewer (<b>#{Rack::Utils::escape_html(blobData[:userName])}</b>) unassigned"
		when EVENT_TYPE::TEST_REVIEWER_ASSIGNED then "Reviewer (<b>#{Rack::Utils::escape_html(blobData[:userName])}</b>) assigned"
		when EVENT_TYPE::TEST_INPROG then "Test in progress"
		when EVENT_TYPE::TEST_PASS_REQ_APPROVAL then "Test passed pending approval"
		when EVENT_TYPE::TEST_PASS then "<b>Test passed</b> and closed"
		when EVENT_TYPE::TEST_FAIL_REQ_APPROVAL then "Test failed pending approval"
		when EVENT_TYPE::TEST_FAIL then "<b>Test failed</b> and closed"
		when EVENT_TYPE::TEST_DELETE then "Test deleted"
		when EVENT_TYPE::USER_LOGIN then "User successfully logged in via #{blobData[:type]}"
		when EVENT_TYPE::USER_LOGIN_FAILURE then "User login failed via #{blobData[:type]}"
		else "UNK"
		end
	end

	def self.getAppAudits(aid)
		appAudits = all(:target_a_type => LINK_TYPE::APPLICATION, :target_a => aid.to_s)
		tests = Application.get(aid).tests
		testAudits = Array.new
		tests.each do |t|
			testAudits << {:tid => t.id, :testName => t.name, :audits => all(:target_a_type => LINK_TYPE::TEST, target_a => t.id.to_s)}
		end

		return {:app => appAudits, :tests => testAudits}
	end

end