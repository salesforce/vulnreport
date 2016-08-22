##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

##
# Format for report exports - references ERB file that templates the report.
class ExportFormat
	include DataMapper::Resource

	property :id,				Serial 		#@return [Integer] Primary Key
	property :name,				String 		#@return [Name] Name of the ExportFormat
	property :description,		Text 		#@return [String] User description of the ExportFormat
	property :erb,				Text 		#@return [String] ERB template code
end