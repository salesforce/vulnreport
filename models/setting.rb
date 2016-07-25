##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

# Vulnreport system setting for DB-stored settings
class Setting
	include DataMapper::Resource

	property :id,				Serial 					#@return [Integer] Primary Key
	property :setting_key,		String, :length => 100 	#@return [String] Setting key
	property :setting_value,	Text 					#@return [String] Setting value
end