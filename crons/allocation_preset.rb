##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

require 'pony'
require 'active_support/core_ext/date_time/calculations'
require 'active_support/time'
require 'date'

##
# Create auto-set allocation for all {User}s marked as using the allocation system.
# @cron Runs first of month at 00:01
class AllocationPreset < VRCron
	vrcron_name :"Monthly Allocation Preset"
	vrcron_type :cron
	vrcron_schedule :"0 0 1 * *"

	##
	# Method invoked when called by the Scheduler job
	# @return [Boolean] Return is a pass-through of {presetAll} - True on success, False otherwise
	def self.cron()
		return presetAll()
	end

	##
	# Create a {MonthlyAllocation} for all {User}s  who had an allocation in the prior month. 
	# Preset will be the same as the previous month and marked as an auto allocation.
	# @return [Boolean] True on success, False otherwise
	def self.presetAll()
		users = User.all(:useAllocation => true, :active => true)
		
		users.each do |u|
			next if(u.lastAllocation.nil?)
			MonthlyAllocation.autoSetAllocationForUser(u.id, u.lastAllocation.allocation)
		end

		return true
	end
end