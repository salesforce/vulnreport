##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

##
# Allocation of time spent on apps for a given month and given {User}. Set by users to represent commitments.
# At the beginning of each month, {AllocationPreset} runs and sets a default MonthlyAllocation with wasAutoSet set to true.
# This default is zero if no previous allocation exists, or equal to the last month's allocation for that User if one exists.
class MonthlyAllocation
	include DataMapper::Resource

	property :id,			Serial 							#@return [Integer] Primary Key
	property :uid,			Integer 						#@return [Integer] ID of {User} this Allocation is for
	property :month,		Integer 						#@return [Integer] Month this Allocation is for (1-12)
	property :year,			Integer 						#@return [Integer] Year this Allocation is for (4 digit year)
	property :allocation,	Integer 						#@return [Integer] Allocation percentage (0-100)
	property :wasAutoSet,	Boolean, :default => false 		#@return [Boolean] True if this allocation was auto-set at beginning of month
	property :wasMgrSet,	Boolean, :default => false 		#@return [Boolean] True if this allocation was set/modified by manager and should be confirmed by user
	property :created_at, 	DateTime 						#@return [DateTime] Date/Time MonthlyAllocation created (DM Handled)
	property :updated_at, 	DateTime 						#@return [DateTime] Date/Time MonthlyAllocation last updated (DM Handled)

	validates_within :allocation, :set => 0..100
	validates_within :month, :set => 1..12

	##
	# Get MonthlyAllocation for a given [User] and given month and year.
	# If no month/year specified, return current month's allocation
	# @return [MonthlyAllocation] Monthly allocation, or nil if none exists for given User/Month/Year combo
	def self.allocationForUser(uid, month=nil, year=nil)
		month = DateTime.now.month if(month.nil?)
		year = DateTime.now.year if(year.nil?)

		return first(:uid => uid, :month => month, :year => year, :order => [:id.desc])
	end

	##
	# Get the most recent MonthlyAllocation set by a {User}. This will NOT return an auto-set allocation.
	# @param uid [Integer] ID of the {User} to get allocation for
	# @return [MonthlyAllocation] Most recent explicitly set or confirmed MonthlyAllocation for given User 
	def self.lastAllocationForUser(uid)
		return first(:uid => uid, :wasAutoSet => false, :order => [:id.desc])
	end

	##
	# Set or update Monthly allocation for a given {User}/month/year combo
	# @param uid [Integer] ID of {User} to set or update MonthlyAllocation for
	# @param allocation [Integer] % allocation (0-100)
	# @param month [Integer] Month to set/update allocation for
	# @param year [Integer] Year to set/update allocation for
	# @return [MonthlyAllocation] New or updated MonthlyAllocation
	def self.setAllocationForUser(uid, allocation, month=nil, year=nil)
		month = DateTime.now.month if(month.nil?)
		year = DateTime.now.year if(year.nil?)

		row = first(:uid => uid, :month => month, :year => year, :order => [:id.desc])
		if(row.nil?)
			row = create(:uid => uid, :allocation => allocation, :month => month, :year => year, :wasAutoSet => false)
		else
			row.update(:allocation => allocation, :wasAutoSet => false)
		end

		return row
	end

	##
	# Automatically set a MonthlyAllocation for a {User}/month/year combo. This method will NOT
	# override an already-created MonthlyAllocation for that combo.
	# @param uid [Integer] ID of {User} to create an auto-set MonthlyAllocation for
	# @param allocation [Integer] % allocation (0-100)
	# @param month [Integer] Month to create an auto-set allocation for
	# @param year [Integer] Year to create an auto-set allocation for
	# @return [MonthlyAllocation] Newly created MonthlyAllocation with wasAutoSet = true
	def self.autoSetAllocationForUser(uid, allocation, month=nil, year=nil)
		month = DateTime.now.month if(month.nil?)
		year = DateTime.now.year if(year.nil?)

		row = first(:uid => uid, :month => month, :year => year, :order => [:id.desc])
		if(row.nil?)
			row = create(:uid => uid, :allocation => allocation, :month => month, :year => year, :wasAutoSet => true)
		else
			#dont overwrite with an autoset
			return nil
		end

		return row
	end
end