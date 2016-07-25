/*
* Copyright (c) 2016, salesforce.com, inc.
* All rights reserved.
* Licensed under the BSD 3-Clause license. 
* For full license text, see LICENSE.txt file in the repo root  or https://opensource.org/licenses/BSD-3-Clause
*/

//Vulnreport system-wide javascript functions
//Page or section specific functions may remain in ERB files

function deleteComment(cid){
  if(confirm("Permanently delete this comment?")){
    $.post("/delComment/" + cid, 
      { _csrf: "<%=csrf_token%>", ajax: true},
      function(){
        $("#commentbody_"+cid).remove();
      }
      ).fail(function(){
        alert("Error deleting comment");
      });
  }
}

$(document).ready(function() {
  $('#notifIcon').on('click', function(){
    if($('#notifIcon').data("viewed") != "true"){
      $.post("/markNotifsSeen", 
        { ajax: true},
        function(){
          $("#notifBadge").remove();
        }
      ).fail(function(){
        console.log("Error marking notifs read");
      });
      $('#notifIcon').data("viewed", "true")
    }
  });
});