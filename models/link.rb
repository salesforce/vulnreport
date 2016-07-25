##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

# Link between entities in Vulnreport or an external system
class Link
	include DataMapper::Resource

	property :id,			Serial 		#@return [Integer] Primary Key
	property :fromType,		Integer		#@return [LINK_TYPE] Type of resource the link is from
	property :fromId,		String 		#@return [String] ID of resource the link is from
	property :toType,		Integer		#@return [LINK_TYPE] Type of resource the link is to
	property :toId,			String 		#@return [String] ID of resource the link is to
end