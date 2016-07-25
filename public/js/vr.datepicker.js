/*
* Copyright (c) 2016, salesforce.com, inc.
* All rights reserved.
* Licensed under the BSD 3-Clause license. 
* For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
*/

function setDateRange(range){
	if(range == 'year'){
		var d = new Date();
		$("#startdate").datepicker("setDate", "01-01-"+d.getFullYear());
		$("#enddate").datepicker("setDate", "12-31-"+d.getFullYear());
	}else if(range == 'lastyear'){
		var d = new Date();
		$("#startdate").datepicker("setDate", "01-01-"+(d.getFullYear()-1));
		$("#enddate").datepicker("setDate", "12-31-"+(d.getFullYear()-1));
	}else if(range == 'month'){
		var d = new Date();
		var s = new Date(d.getFullYear(), d.getMonth(), 1);
		var e = new Date(d.getFullYear(), d.getMonth() + 1, 0);
		$("#startdate").datepicker("setDate", (s.getMonth()+1)+"-"+s.getDate()+"-"+s.getFullYear());
		$("#enddate").datepicker("setDate", (e.getMonth()+1)+"-"+e.getDate()+"-"+e.getFullYear());
	}else if(range == 'lastmonth'){
		var d = new Date();
		if(d.getMonth() == 1){
			var s = new Date(d.getFullYear()-1, 12, 1);
			var e = new Date(d.getFullYear()-1, 12, 0);
		}else{
			var s = new Date(d.getFullYear(), d.getMonth()-1, 1);
			var e = new Date(d.getFullYear(), d.getMonth(), 0);
		}
		$("#startdate").datepicker("setDate", s);
		$("#enddate").datepicker("setDate", e);
	}else if(range == 'quarter'){
		var d = new Date();
		if(d.getMonth()+1 >= 2 && d.getMonth()+1 <= 4){
			$("#startdate").datepicker("setDate", "02-01-"+d.getFullYear());
			$("#enddate").datepicker("setDate", "04-30-"+d.getFullYear());
		}else if(d.getMonth()+1 >= 5 && d.getMonth()+1 <= 7){
			$("#startdate").datepicker("setDate", "05-01-"+d.getFullYear());
			$("#enddate").datepicker("setDate", "07-31-"+d.getFullYear());
		}else if(d.getMonth()+1 >= 8 && d.getMonth()+1 <= 10){
			$("#startdate").datepicker("setDate", "08-01-"+d.getFullYear());
			$("#enddate").datepicker("setDate", "10-31-"+d.getFullYear());
		}else if(d.getMonth()+1 == 11 || d.getMonth()+1 == 12){
			$("#startdate").datepicker("setDate", "11-01-"+d.getFullYear());
			$("#enddate").datepicker("setDate", "01-31-"+(d.getFullYear()+1));
		}else if(d.getMonth()+1 == 1){
			$("#startdate").datepicker("setDate", "11-01-"+(d.getFullYear()-1));
			$("#enddate").datepicker("setDate", "01-31-"+d.getFullYear());
		}
	}else if(range == 'lastquarter'){
		var d = new Date();
		if(d.getMonth()+1 >= 2 && d.getMonth()+1 <= 4){
			$("#startdate").datepicker("setDate", "11-01-"+(d.getFullYear()-1));
			$("#enddate").datepicker("setDate", "01-31-"+d.getFullYear());
		}else if(d.getMonth()+1 >= 5 && d.getMonth()+1 <= 7){
			$("#startdate").datepicker("setDate", "02-01-"+d.getFullYear());
			$("#enddate").datepicker("setDate", "04-30-"+d.getFullYear());
		}else if(d.getMonth()+1 >= 8 && d.getMonth()+1 <= 10){
			$("#startdate").datepicker("setDate", "05-01-"+d.getFullYear());
			$("#enddate").datepicker("setDate", "07-31-"+d.getFullYear());
		}else if(d.getMonth()+1 == 11 || d.getMonth()+1 == 12 || d.getMonth()+1 == 1){
			$("#startdate").datepicker("setDate", "08-01-"+d.getFullYear());
			$("#enddate").datepicker("setDate", "10-31-"+d.getFullYear());
		}
	}else if(range == 'fy'){
		var d = new Date();
		if(d.getMonth()+1 == 1){
			$("#startdate").datepicker("setDate", "02-01-"+(d.getFullYear()-1));
			$("#enddate").datepicker("setDate", "01-31-"+d.getFullYear());
		}else{
			$("#startdate").datepicker("setDate", "02-01-"+d.getFullYear());
			$("#enddate").datepicker("setDate", "01-31-"+(d.getFullYear()+1));
		}
	}else if(range == 'fytd'){
		var d = new Date();
		if(d.getMonth()+1 == 1){
			$("#startdate").datepicker("setDate", "02-01-"+(d.getFullYear()-1));
			$("#enddate").datepicker("setDate", (d.getMonth()+1)+"-"+d.getDate()+"-"+d.getFullYear());
		}else{
			$("#startdate").datepicker("setDate", "02-01-"+d.getFullYear());
			$("#enddate").datepicker("setDate", (d.getMonth()+1)+"-"+d.getDate()+"-"+d.getFullYear());
		}
	}else if(range == 'lastfy'){
		var d = new Date();
		if(d.getMonth()+1 == 1){
			$("#startdate").datepicker("setDate", "02-01-"+(d.getFullYear()-2));
			$("#enddate").datepicker("setDate", "01-31-"+(d.getFullYear()-1));
		}else{
			$("#startdate").datepicker("setDate", "02-01-"+(d.getFullYear()-1));
			$("#enddate").datepicker("setDate", "01-31-"+d.getFullYear());
		}
	}else if(range == 'all'){
		var d = new Date();
		$("#startdate").datepicker("setDate", "01-01-2012");
		$("#enddate").datepicker("setDate", (d.getMonth()+1)+"-"+d.getDate()+"-"+d.getFullYear());
	}
}