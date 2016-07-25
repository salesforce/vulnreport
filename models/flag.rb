##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

##
# Flags to be assigned to {Application}s
class Flag
	include DataMapper::Resource

	property :id, 				Serial 						#@return [Integer] Primary Key
	property :active,			Boolean, :default => true 	#@return [Boolean] True if this Flag is active and available for use
	property :name,				String 						#@return [Name] Name of the Flag
	property :description,		Text 						#@return [String] User description of the Flag
	property :icon,				String						#@return [String] Name of the fa icon to use for this flag (optional) (e.g. info for fa-info)

	has n, :applications,			:through => Resource

end