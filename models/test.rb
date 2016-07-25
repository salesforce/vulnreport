##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

##
# A single security test of an {Application}
class Test
	include DataMapper::Resource

	property :id, 					Serial 						#@return [Integer] Primary Key
	property :application_id,  		Integer   					#@return [Integer] ID of {Application} the Test belongs to
	property :name, 				String, :length => 100 		#@return [String] Test name
	property :description, 			Text 						#@return [String] Test description
	property :org_created,			Integer, :default => 1		#@return [Integer] ID of {Organization} that created Test
	property :reviewer, 			Integer 					#@return [Integer] ID of {User} who is reviewer for Test
	property :ext_eid,				String 						#@return [String] External entity ID for this test (reference only)
	
	property :created_at, 			DateTime 					#@return [DateTime] Date/Time this Test was created (DM handled)
	property :updated_at, 			DateTime 					#@return [DateTime] Date/Time this Test was last updated (DM handled)
	property :pending_at,			DateTime					#@return [DateTime] Date/Time this Test was put into pending approval state
	property :con_closed_at,		DateTime					#@return [DateTime] Date/Time this Test was closed by contractor (nil if not contractor test)
	property :closed_at, 			DateTime					#@return [DateTime] Date/Time this Test was closed (completed)

	property :contractor_test,		Boolean, :default => false 	#@return [Boolean] True if this test is being done by a contractor
	property :is_pending,			Boolean, :default => false 	#@return [Boolean] True if this test is currently pending approver review
	property :pending_by,			Integer 					#@return [Integer] ID of the {User} who put this test in pending state
	property :pending_pass,			Boolean, :default => false 	#@return [Boolean] True if this test is pending review to be passed, false if failed
	
	property :approved_by,			Integer, :default => 0 		#@return [Integer] UID of {User} who approved or rejected approval flow results
	property :disagree_reason,		Text 						#@return [String] Reason {#approved_by} {User} disagreed with approval flow results
	property :complete,				Boolean, :default => false 	#@return [Boolean] True if Test is complete. Only true when entire test is complete / all approvals done
	property :pass,					Boolean, :default => false 	#@return [Boolean] True if Test is passed (True if prov pass)
	property :provPassReq,			Boolean, :default => false 	#@return [Boolean] True if provisional pass has been requested
	property :provPass,				Boolean, :default => false 	#@return [Boolean] True if provisional pass has been approved
	property :provPassRequestor,	Integer, :default => 0 		#@return [Integer] UID of {User} who requested provisional pass
	property :provPassApprover,		Integer, :default => 0 		#@return [Integer] UID of {User} who approved the provisional pass
	property :provPassExpiry,		Date 						#@return [Date] Date the Prov Pass for this test will expire


	belongs_to :application, :required => false 				#@return [Application] Application this Test belongs to
	has n, :vulnerabilities

	##
	# Get HTML string of icon representing Test's status
	# @return [String] HTML of icon for Test's status
	def status_icon
		return '<i class="fa fa-clock-o" rel="tooltip" title="Test Awaiting Review"></i> <i class="fa fa-check" rel="tooltip" title="Pending Pass" style="color:#009933; opacity:0.4"></i>' if (!complete && is_pending && pending_pass && !provPassReq)
		return '<i class="fa fa-clock-o" rel="tooltip" title="Test Awaiting Review"></i> <i class="fa fa-frown-o" rel="tooltip" title="Pending Fail" style="color:#B40404; opacity:0.4""></i>' if (!complete && is_pending && !pending_pass && !provPassReq)
		return '<i class="fa fa-clock-o" rel="tooltip" title="Test Awaiting Review"></i>' if (!complete && is_pending && !provPassReq)
		return '<i class="fa fa-warning" rel="tooltip" title="Provisional Pass Requested" style="color:#EEA236; opacity:0.4;"></i>' if (!complete && pass && provPassReq && !provPass)
		return '<i class="fa fa-check" rel="tooltip" title="Provisional Pass" style="color:#EEA236;"></i>' if (complete && pass && provPassReq && provPass)
		return '<i class="fa fa-clock-o" rel="tooltip" title="Test In Progress"></i>' if (!complete)
		return '<i class="fa fa-check" rel="tooltip" title="Test Passed" style="color:#009933;"></i>' if (complete && pass)
		return '<i class="fa fa-frown-o" rel="tooltip" title="Test Failed" style="color:#B40404;"></i>' if (complete && !pass)
	end

	##
	# Get HTML string of text representing Test's status
	# @return [String] HTML text for Test's status
	def status_text
		return "Awaiting Review" if (!complete && is_pending && !provPassReq)
		return '<span style="color:#EEA236;">Provisional Requested</span>' if (!complete && pass && provPassReq && !provPass)
		return '<span style="color:#EEA236;">Provisionally Passed</span>' if (complete && pass && provPassReq && provPass)
		return "In Progress" if (!complete)
		return '<span style="color:#009933;">Test Passed</span>' if (complete && pass)
		return '<span style="color:#B40404;">Test Failed</span>' if (complete && !pass)
	end

	##
	# Get all verified {Vulnerability} objects attached to this Test
	# @return [Array<Vulnerability>] Vulnerabilities
	def verified_vulns
		return vulnerabilities(:verified => true, :falsepos => false).sort{ |x,y| x.vuln_priority <=> y.vuln_priority }
	end

	##
	# Returns Application.isLinked? for parent {Application}
	# @return [Boolean] True if parent Application is linked
	def isAppLinked?
		return self.application.isLinked?
	end

	##
	# Get the parent {Application}'s {RecordType} ID
	# @return [Integer] ID of parent Application's RecordType
	def record_type
		return self.application.record_type
	end

	##
	# Get name of Test's reviewer
	# @return [String] Name of reviewer of this test
	def reviewerName
		return User.get(self.reviewer).name
	end

	##
	# Get all Tests created by given OrgId
	# @param oid [Integer] ID of {Organization} to get Tests created by
	# @return [Array<Test>] All Tests created by given Organization
	def self.createdBy(oid)
		all(:org_created => oid, :order => [ :id.desc ])
	end

	##
	# Get Tests that are on apps with any of the given flags and match given parameters.
	# This method passes through to Test.all with additional parameters to properly filter by flag
	# @param selectedFlags [Array] Array of flag IDs to filter by
	# @param params [Hash] Additional params to pass to Test.all
	# @return [Array<Test>] Matching Tests
	def self.allWithFlags(selectedFlags, params={})
		if(selectedFlags.include?(-1))
			return all(params)
		else
			return all({Test.application.flags.id => selectedFlags}.merge(params))
		end
	end

	##
	# Count Tests that have the given flags and match given parameters.
	# This method passes through to Test.count with additional parameters to properly filter by flag
	# @param selectedFlags [Array<Integer>] Flags to filter by
	# @param params [Hash] Additional params to pass to Test.count
	# @return [Array<Test>] Number of matching Tests
	def self.countWithFlags(selectedFlags, params={})
		return allWithFlags(selectedFlags, params.merge({:fields => [:id]})).size
	end
end