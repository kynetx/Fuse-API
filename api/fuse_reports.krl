ruleset fuse_reports {
    meta {
        name "Module for Reports"

        description <<
Functions for creating the Fuse reports
        >>
        author "PJW"

        errors to b16x13

	use module b16x19 alias common

        sharing on
        provides fleetReport, emailBody 
    }

    global {

      tripDuration = function(trip) {
        (time:strftime(trip{"endTime"}, "%s") - time:strftime(trip{"startTime"}, "%s"))/60
      };

      emailBody = function(html) {
        body = <<
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org=/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html>
<body bgcolor="f1f1f1" topmargin="0" bottommargin="0" leftmargin="0" rightmargin="0" style="margin:0;padding:0;">
<table cellspacing="0" cellpadding="0" border="0" width="600" align="center" bgcolor="f1f1f1">


#{html} 

<tr>
 <td bgcolor="f1f1f1" style="padding:30px;text-align:center">
You are receiving this email because you have vehicles in Fuse. <br/>
You can stop receiving them by <a href="http://joinfuse.com/app.html">editing your report preferences</a> at Joinfuse.com<br/>
<p>
<img align="center" src="https://s3.amazonaws.com/Fuse_assets/img/fuse_logo-30.png"/>
</p>
&copy; Kynetx, Inc.
 </td>
</tr> 


</table><!-- main -->
</body>
</html>
>>;
	body
      };

      fleetReport = function(period, tz, summaries) {

        today = time:strftime(time:now(), "%Y%m%dT000000%z", {"tz":"UTC"});
        yesterday = time:add(today, {"days": -1});
        before = time:add(today, period{"format"});

        friendly_format = "%b %e";
	title = "Fuse Fleet Report for #{time:strftime(before, friendly_format)} to #{time:strftime(yesterday, friendly_format)}"; 

	wrap_in_div = function(obj, class) {
  	  div = <<
<div class="#{class}">#{obj}</div>
>>;
          div
        };

        wrap_in_span = function(obj, class) {
          span = <<
<span class="#{class}">#{obj}</span>
>>;
          span
        };

        format_trip_line = function(trip) {
          cost = trip{"cost"}.isnull() || trip{"cost"} < 0.01 => ""
                                                               | "$" + trip{"cost"}.sprintf("%.2f");
          len = trip{"mileage"}.isnull() || trip{"mileage"} < 0.01 => ""
                                                                    | trip{"mileage"} + " miles";
          name = trip{"name"}.isnull() || trip{"name"} eq "" => "none"
                                                              | trip{"name"};
          time = trip{"endTime"}.isnull() => ""
                                           | time:strftime(trip{"endTime"}, "%b %e %I:%M %p", {"tz": tz});

          duration_val = tripDuration(trip);
          duration = duration_val < 0.1 => ""
                                         | wrap_in_span(duration_val.sprintf("%.01f") + " min", "trip_duration");

          odd_line_style = "font-family:Arial, sans-serif;font-size:14px;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:#aaa;color:#333;background-color:#fff;";
          even_line_style = "font-family:Arial, sans-serif;font-size:14px;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:#aaa;color:#333;background-color:#fff;background-color:#FCFBE3";

          line = <<
<tr>
<td style="#{odd_line_style}">#{time}</td>
<td style="#{odd_line_style}">#{name}</td>
<td style="#{odd_line_style}">#{len}</td>
<td style="#{odd_line_style}">#{cost}</td>
<td style="#{odd_line_style}">#{duration}</td>
</tr>
>>;
          line
        };

        aggregate_two_trips = function(a,b) {
          {"cost": a{"cost"} + b{"cost"},
           "mileage" : a{"mileage"} + b{"mileage"},
           "duration": a{"duration"} + tripDuration(b)
          }
        };

        format_vehicle_summary = function(vehicle) {
          name = vehicle{"profileName"};
          photo = vehicle{"profilePhoto"};
          address = vehicle{"address"} || "";
          gas = vehicle{"fuellevel"}.isnull() => ""
                                               | "Fuel remaining: " + vehicle{"fuellevel"} + "%";

          mileage = vehicle{"mileage"}.isnull() => ""
                                                 | "Odometer: " + vehicle{"mileage"};
          vin = vehicle{"vin"}.isnull() => "No VIN Recorded"
                                         | "VIN: " + vehicle{"vin"};


          trips_raw = vehicle{"channel"}.isnull() => []
                    | common:skycloud(vehicle{"channel"},"b16x18","tripsByDate", {"start": before, "end": today});
          trips = trips_raw.typeof() eq "hash" && trips_raw{"error"} => [].klog(">>> error for trips query to " + vehicle{"channel"})
                                                                      | trips_raw;  

          trips_html = trips.map(format_trip_line).join(" ");

          trip_aggregates = trips.reduce(aggregate_two_trips, {"cost":0,"mileage":0,"duration":0}).klog(">>>> aggregates>>>>");
          total_duration = trip_aggregates{"duration"}.sprintf("%.0f");       
          total_miles = trip_aggregates{"mileage"}.sprintf("%.1f");
          total_cost = trip_aggregates{"cost"}.sprintf("%.2f"); 
          num_trips = trips.length(); 

          find_avg = function(x, n) {
            num_trips > 0 => x / n
                           | 0;
          };

          avg_duration = find_avg(trip_aggregates{"duration"}, num_trips).sprintf("%.0f");       
          avg_miles = find_avg(trip_aggregates{"mileage"}, num_trips).sprintf("%.1f");
          avg_cost = find_avg(trip_aggregates{"cost"}, num_trips).sprintf("%.2f"); 

          longest = trips.reduce(function(a,b){
                                  a{"mileage"} < b{"mileage"} => {"trip": b, "mileage": b{"mileage"}}
                                                               | a
                                 }, 
                                 {"trip": {}, "mileage": 0}
                                ).klog(">>>> longest >>>>");


          trip_table_header_style = "font-family:Arial, sans-serif;font-size:14px;font-weight:normal;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:#aaa;color:#fff;background-color:#f38630;";

          vehicle_table_row_style = "text-align=left;font-family:Arial,sans-serif;font-size:14px;padding:10px 5px  0px 10px;border-style:solid;border-width:0px;overflow:hidden;word-break:normal;";

          line = <<
<table width="100%" style="style="width:550px;border-collapse:collapse;border-spacing:0;">
<tr>
 <td style="width:120px;#{vehicle_table_row_style}">
  <img border="1" style="border:1px solid #e6e6e6;" src="#{photo}" align="left"/>
 </td>
 <td style="#{vehicle_table_row_style}">
  <div style="font-size:x-large">#{name}</div>

  <div class="vehicle_address">#{address}</div>
  <div class="vehicle_vin">#{vin}</div> 
  <div class="vehicle_mileage">#{mileage}</div>
  <div class="vehicle_fuellevel">#{gas}</div>
 </td>
</tr>
<tr style="">
 <td colspan="2" style="font-size:large;margin-top:50px;#{vehicle_table_row_style}">
  Trips from Last Week
 </td>
</tr>

<tr><td colspan="2" style="#{vehicle_table_row_style}"><b>#{name} took #{num_trips} trips: #{total_miles} miles, #{total_duration} min, $#{total_cost}</b></td></tr>
<tr><td colspan="2" style="#{vehicle_table_row_style}">Trip averages: #{avg_miles} miles, #{avg_duration} min, $#{avg_cost}</b></td></tr>

<tr>
 <td colspan="2" style="#{vehicle_table_row_style}">
  <table class="trip" style="width:545px;border-collapse:collapse;border-spacing:0;border-color:#aaa;">
   <tr>
    <th colspan="5" style="text-align:center;#{trip_table_header_style}">#{name} Trips</th>
   </tr>
   <tr>
    <th style="#{trip_table_header_style}">Date</th>
    <th style="#{trip_table_header_style}">Name</th>
    <th style="#{trip_table_header_style}">Length</th>
    <th style="#{trip_table_header_style}">Cost</th>
    <th style="#{trip_table_header_style}">Duration</th>
   </tr>

#{trips_html} 

  </table>
 </td>
</tr><!-- trips -->
</table><!-- vehicle -->
>>;
          line
        }; // format_vehicle_summary

        vehicle_html = summaries.map(format_vehicle_summary).join(" ");


        html = <<

<tr>
 <td width="600" bgcolor="#f1f1f1">
  <img src="https://s3.amazonaws.com/Fuse_assets/img/email-header.png" width="600" border="0" align="top"/>
 </td>
</tr>

<tr>
 <td bgcolor="ffffff" style="text-align:center;">
  <h2>#{title}</h2>
 </td>
</tr>

<tr>
 <td bgcolor="ffffff" style="text-align:left;">
  #{vehicle_html}
 </td>
</tr>



>>;
      emailBody(html)
    }
  }
}
// fuse_reports.krl