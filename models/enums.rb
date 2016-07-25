##
# Copyright (c) 2016, salesforce.com, inc.
# All rights reserved.
# Licensed under the BSD 3-Clause license. 
# For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
##

# Enum for type of section on a {Vulnerability}
module SECT_TYPE
	BURP = 0
	URL = 1
	FILE = 2
	SSHOT = 3
	OUTPUT = 4
	CODE = 5
	NOTES = 6
	PAYLOAD = 7
	MULTI = 99 #used for multi-add forms
end

# Enum for what type of entity a {Link} is connected to
module LINK_TYPE
	#Vulnreport 1-9
	APPLICATION = 1
	TEST = 2
	ORGANIZATION = 3
	USER = 4
	VULN = 5
	COMMENT = 6
	AUDITREC = 8

	#{VRLinkedObject} Link ID
	VRLO = 9
	
	#VR Perms 1xx
	ALLOW_APP_RT = 101
end

# Enum for vuln priority
module VULN_PRIORITY
	CRITICAL = 0
	HIGH = 1
	MEDIUM = 2
	LOW = 3
	INFORMATIONAL = 4
	NONE = 99
end

#Enum for geographic region
module GEO
	#AMER 1-9
	USA = 1
	NA = 2
	CA = 3
	SA = 4
	
	#APAC 11-19
	JP = 11
	CN = 12
	APAC = 13
	
	#EMEA 21-29
	UK = 21
	EU = 22
	EMEA = 23
end

# Enum for type of {Notification}
module NOTIF_CLASS
	# Comments 1-9 
	COMMENT_APP = 1
	COMMENT_TEST = 2
	COMMENT_VULN = 3
	COMMENT_APP_APPROVER = 4
	COMMENT_TEST_APPROVER = 5
	COMMENT_VULN_APPROVER = 6
	
	# Replies 11-19
	REPLY_TO_COMMENT = 11
	
	# Approvals 21-29
	PROV_PASS_REQUEST = 21
	PROV_PASS_APPROVE = 22
end

# Enum for Audit Records
module EVENT_TYPE
	## Provisional Passes ##
	PROV_PASS_REQUEST = 11
	PROV_PASS_APPROVE = 12
	PROV_PASS_DENY = 13
	PROV_PASS_REQCANCEL = 14
	
	## General Audit ##
	ADMIN_OVERRIDE_PRIVATE_APP = 21
	ADMIN_OVERRIDE_PRIVATE_TEST = 22

	## Application-based 10x ##
	APP_CREATE = 101
	APP_RENAME = 102
	APP_LINK = 103
	APP_UNLINK = 104
	APP_MADE_PRIVATE = 105
	APP_MADE_NOTPRIVATE = 106
	APP_MADE_GLOBAL = 107
	APP_MADE_NOTGLOBAL = 108
	APP_RTCHANGE = 109
	APP_DELETE = 110
	APP_GEO_SET = 111
	APP_FLAG_ADD = 112
	APP_FLAG_REM = 113
	APP_OWNER_ASSIGN = 114

	## Test-based 20x ##
	TEST_CREATE = 201
	TEST_RENAME = 202
	TEST_REVIEWER_UNASSIGNED = 203
	TEST_REVIEWER_ASSIGNED = 204
	TEST_INPROG = 205
	TEST_PASS_REQ_APPROVAL = 206
	TEST_PASS = 207
	TEST_FAIL_REQ_APPROVAL = 208
	TEST_FAIL = 209
	TEST_DELETE = 210

	## Monitors - 90x ##
	# Fill in here as needed for custom crons, alerts, etc.
	# See documentation for more details
end

# Fill in here as needed for custom alerts - see documentation
MONITOR_EVENT_TYPES = []

# Enum for panel types in {DashConfig}'s
module DASHPANEL_TYPE
	## Defaults - 0x ##
	MYACTIVE = 1 #all
	MYACTIVE_RT = 2 #specific type
	MY_WNO_TESTS = 3
	MY_WNO_TESTS_RT = 4

	## Require a RT - 1x ##
	STATUS_NEW_AND_INPROG = 11
	STATUS_PASSED = 14
	STATUS_FAILED = 15
	ALL_APPS = 16
	APPS_WNO_TESTS = 17
	STATUS_CLOSED = 18

	## User Specific - 2x ##
	MY_PASSED = 21
	MY_FAILED = 22
	MY_ALL = 23
	MY_APPROVALS = 24 #all pending approvals for user
	MY_APPROVALS_RT = 19 #pending approvals for user of given RT
end

NON_RT_DASHPANELS = [DASHPANEL_TYPE::MYACTIVE,DASHPANEL_TYPE::MY_WNO_TESTS,DASHPANEL_TYPE::MY_PASSED,DASHPANEL_TYPE::MY_FAILED,DASHPANEL_TYPE::MY_ALL,DASHPANEL_TYPE::MY_APPROVALS];
