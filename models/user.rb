##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

##
# Represents a Vulnreport user
class User
	include DataMapper::Resource

	property :id,				Serial							#@return [Integer] Primary Key
	property :sso_user,			String, :length => 500			#@return [String] SSO-passed username
	property :sso_id,			String							#@return [String] SSO-passed User EID 005xxx...
	property :username,			String							#@return [String] Non-SSO username. If created via SSO, defaults to {sso_user}
	property :password,			BCryptHash						#@return [String] Non-SSO password. If created via SSO, defaults to nil. If nil, user cannot login using it
	
	property :extEID,			String							#@return [String] User external EID if separate from SSO ID
	property :email,			String, :length => 500			#@return [String] User email address
	property :name,				String, :length => 100			#@return [String] User name.
	property :initials,			String							#@return [String] User initials
	property :org,				Integer							#@return [Integer] {Organization} ID of org the user belongs to. 0 = unverified
	property :defaultGeo,		Integer, :default => GEO::USA	#@return [GEO] Default {GEO} for User
	property :active,			Boolean, :default => true		#@return [Boolean] User is active. False will disable and override all other perms
	property :dashOverride,		Integer, :default => -1			#@return [Integer] ID of {DashConfig} User has chosen to override default dash for org with. -1 if no override.
	property :useAllocation,	Boolean, :default => false 		#@return [Boolean] True if this user uses the {MonthlyAllocation} system
	property :allocCoeff,		Integer, :default => 200 		#@return [Integer] The coefficient for allocation calculation. The number represents the total number of reviews the User would complete if tasked 100% for a year.
	property :manager_id,		Integer							#@return [Integer] The ID of the {User} marked as this user's manager. Nil if no manager.
	
	property :admin,			Boolean, :default => false		#@return [Boolean] Perm bit. True if is a Vulnreport admin
	property :reportsOnly,		Boolean, :default => false		#@return [Boolean] Perm bit. If true, only allowed to view reports, nothing else. OVERRIDES other perms.
	property :canAuditMonitors,	Boolean, :default => false		#@return [Boolean] Perm bit. True if allowed to audit monitor trigger logs
	property :provPassApprover,	Boolean, :default => false		#@return [Boolean] Perm bit. True if allowed to approve provisional pass requests
	property :canPassToCon,		Boolean, :default => false		#@return [Boolean] Perm bit. True if allowed to pass an app to a contractor
	property :requireApproval,	Boolean, :default => false		#@return [Boolean] Perm bit. True if this user needs approval to pass/fail a test

	property :approver_users,	CommaSeparatedList				#@return [Integer] IDs of {User}s who can approve for this user. Nil if none can.
	property :approver_orgs,	CommaSeparatedList				#@return [Integer] IDs of {Organization}s who can approve for this user. Nil if none can.

	def allocation
		return MonthlyAllocation.allocationForUser(self.id)
	end

	def lastAllocation
		return MonthlyAllocation.lastAllocationForUser(self.id)
	end

	def orgname
		return nil if(self.org == 0)
		return Organization.get(self.org).name
	end

	def organization
		return nil if(self.org == 0)
		return Organization.get(self.org)
	end

	def verified?
		if(self.org == 0)
			return false
		else
			return true
		end
	end

	def contractor?
		return false if(self.org == 0)
		o = Organization.get(self.org)
		return o.contractor
	end

	def manager
		return nil if(self.manager_id.nil? || self.manager_id <= 0)
		return User.get(self.manager_id)
	end

	def isManager?
		return (User.count(:manager_id => self.id) > 0)
	end

	def requiresApproval?
		if(self.requireApproval)
			return true
		else
			o = Organization.get(self.org)
			if(o.nil?)
				return false
			else
				return o.requireApproval
			end
		end
	end

	def approvers
		if(self.requireApproval)
			return {:users => self.approver_users, :orgs => self.approver_orgs}
		else
			o = Organization.get(self.org)
			if(o.nil?)
				return {:users => nil, :orgs => nil}
			else
				return {:users => o.approver_users, :orgs => o.approver_orgs}
			end
		end
	end

	def lastLogin
		return AuditRecord.first(:event_type => EVENT_TYPE::USER_LOGIN, :actor => self.id, :order => [:event_at.desc])
	end

	def self.activeUsers
		return all(:active => true)
	end

	def self.activeSorted
		users = all(:active => true, :name.not => nil, :name.not => "")
		users.sort{|x,y| x.name.split(" ").last <=> y.name.split(" ").last }
	end
end