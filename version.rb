##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

class Vulnreport
	module VERSION
		MAJOR = 3
		MINOR = 0
		PATCH = 3
		PRE = nil
		
		STRING = [MAJOR,MINOR,PATCH,PRE].compact.join(".")
	end
end