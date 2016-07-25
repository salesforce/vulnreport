##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

##
# Represents a group of {User}s, usually by functional team. Some parts of permissions model based around Organization membership.
class Organization
	include DataMapper::Resource

	property :id,				Serial 							#@return [Integer] Primary Key
	property :name,				String 							#@return [String] Organization name
	property :super,			Boolean, :default => false 		#@return [Boolean] True if this Organization is Super (can view all {Application}s). While not deprecated, this is rarely used with the new permissions model.
	property :contractor,		Boolean, :default => false 		#@return [Boolean] True if this Organization is a contractor group
	property :dashconfig,		Integer, :default => 0			#@return [Integer] The dashboard configuration {User}s in this org should see. 0 represents default dash
	
	property :canReport,		Boolean, :default => true 		#@return [Boolean] True if this Organization's {User}s can use reporting tools
	property :requireApproval,	Boolean, :default => false		#@return [Boolean] Perm bit. True if this user needs approval to pass/fail a test

	property :approver_users,	CommaSeparatedList				#@return [Integer] IDs of {User}s who can approve for this user. Nil if none can.
	property :approver_orgs,	CommaSeparatedList				#@return [Integer] IDs of {Organization}s who can approve for this user. Nil if none can.

	##
	# Get all active {User}s belonging to the Organization
	# @return [Array<User>] Active {User}s who are members of the Organization
	def activeUsers
		return User.all(:active => true, :org => self.id)
	end

	##
	# Get all {User}s belonging to the Organization
	# @return [Array<User>] All {User}s who are members of the Organization
	def allUsers
		return User.all(:org => self.id)
	end
end