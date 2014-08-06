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
        provides fleetReport, emailBody, fleetDetails
    }

    global {

      tripDuration = function(trip) {
        (time:strftime(trip{"endTime"}, "%s") - time:strftime(trip{"startTime"}, "%s"))
      };

      find_avg = function(x, n) {
        n > 0 => x / n
               | 0;
      };

      aggregate_two_trips = function(a,b) {
        {"cost": a{"cost"} + b{"cost"},
         "mileage" : a{"mileage"} + b{"mileage"},
         "duration": a{"duration"} + tripDuration(b)
        }
      };

      aggregate_two_fillups = function(a,b) {
        {"cost": a{"cost"} + b{"cost"},
         "volume" : a{"volume"} + b{"volume"}
        }
      };

      add_maps = function(a, b) {
        a.map(function(k,v) {v + b{k}} )
      };

      fleetDetails = function(start, end, summaries) {
  	fleet_data = summaries
                         .map(vehicleDetails(start, end));
//                         .reduce(function(a, b){a.map(function(k,v){ v.append( b{k}) })});

	fleet_data
      }

      vehicleDetails = function(start, end) {
        function(vehicle) {
          trips_raw = vehicle{"channel"}.isnull() => []
                    | common:skycloud(vehicle{"channel"},"b16x18","tripsByDate", {"start": start, "end": end});
          trips = trips_raw.typeof() eq "hash" && trips_raw{"error"} => [].klog(">>> error for trips query to " + vehicle{"channel"})
                                                                      | trips_raw;  

          trip_aggregates = trips.reduce(aggregate_two_trips, {"cost":0,"mileage":0,"duration":0}).klog(">>>> trip aggregates >>>>");
          total_duration = trip_aggregates{"duration"}.sprintf("%.0f");       
          total_miles = trip_aggregates{"mileage"}.sprintf("%.1f");
          total_cost = trip_aggregates{"cost"}.sprintf("%.2f"); 
          num_trips = trips.length(); 

	  total_trips = {"num": num_trips,
	                 "miles": total_miles,
			 "cost": total_cost,
			 "duration": total_duration
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


	  fillups_raw = vehicle{"channel"}.isnull() => []
                      | common:skycloud(vehicle{"channel"},"b16x20","fillupsByDate", {"start": start, "end": end}).klog(">>>>> seeing fillups >>>>>>");
          fillups = fillups_raw.typeof() eq "hash" && fillups_raw{"error"} => [].klog(">>> error for fillups query to " + vehicle{"channel"})
                                                                            | fillups_raw;  


          fillups_aggregates = fillups.reduce(aggregate_two_fillups, {"cost":0,"volume":0}).klog(">>>> fillups aggregates >>>>");
	  total_fillups = {"num": fillups.length(),
	   	           "cost": fillups_aggregates{"cost"},
	   	           "volume": fillups_aggregates{"volume"}
	                  };

	  {"profileName" : vehicle{"profileName"},
	   "profilePhoto" : vehicle{"profilePhoto"},
	   "address" : vehicle{"address"} || "",
	   "fuellevel" : vehicle{"fuellevel"},
	   "mileage" : vehicle{"mileage"},
	   "vin": vehicle{"vin"},
	   "tripTotals" : total_trips,
	   "tripAverages": {"duration" : avg_duration,
	                    "miles" : avg_miles,
			    "cost" : avg_cost
	                   },
	   "trips" : trips, 
	   "fuelTotals" : total_fillups,
	   "fillups" : fillups
	  }   


        }
      }

      emailBody = function(html) {
        body = <<
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org=/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html>
<body bgcolor="f1f1f1" topmargin="0" bottommargin="0" leftmargin="0" rightmargin="0" style="margin:0,padding:0;">
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

	fleet_details = fleetDetails(before, today, summaries);

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

        odd_line_style = "font-family:Arial, sans-serif;font-size:14px;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:#aaa;color:#333;background-color:#fff;";
        even_line_style = "font-family:Arial, sans-serif;font-size:14px;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:#aaa;color:#333;background-color:#fff;background-color:#FCFBE3";
        trip_table_header_style = "font-family:Arial, sans-serif;font-size:14px;font-weight:normal;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:#aaa;color:#fff;background-color:#f38630;";
        vehicle_table_row_style = "text-align=left;font-family:Arial,sans-serif;font-size:14px;padding-left:10px;border-style:solid;border-width:0px;overflow:hidden;word-break:normal;";



        format_trip_line = function(trip) {
          cost = trip{"cost"}.isnull() || trip{"cost"} < 0.01 => ""
                                                               | "$" + trip{"cost"}.sprintf("%.2f");
          len = trip{"mileage"}.isnull() || trip{"mileage"} < 0.01 => ""
                                                                    | trip{"mileage"} + " miles";
          name = trip{"name"}.isnull() || trip{"name"} eq "" => ""
                                                              | trip{"name"};
          time = trip{"endTime"}.isnull() => ""
                                           | time:strftime(trip{"endTime"}, "%b %e %I:%M %p", {"tz": tz});

          duration_val = tripDuration(trip)/60; // minutes
          duration = duration_val < 0.1 => ""
                                         | wrap_in_span(duration_val.sprintf("%.01f") + " min", "trip_duration");

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

        format_fillup_line = function(fillup) {
          cost = fillup{"cost"}.isnull() || fillup{"cost"} < 0.01 => ""
                                                               | "$" + fillup{"cost"}.sprintf("%.2f");
          volume = fillup{"volume"}.isnull() || fillup{"volume"} < 0.01 => ""
                                                                    | fillup{"volume"}.sprintf("%.1f") ;
          location = fillup{"location"}.isnull() || fillup{"location"} eq "" => ""
                                                              | fillup{"location"};
          time = fillup{"timestamp"}.isnull() => ""
                                           | time:strftime(fillup{"timestamp"}, "%b %e %I:%M %p", {"tz": tz});

          mpg = fillup{"mpg"} < 0.1 => ""
                                     | fillup{"mpg"}.sprintf("%.1f");

          line = <<
<tr>
<td style="#{odd_line_style}">#{time}</td>
<td style="#{odd_line_style}">#{location}</td>
<td style="#{odd_line_style}">#{volume}</td>
<td style="#{odd_line_style}">#{cost}</td>
<td style="#{odd_line_style}">#{mpg}</td>
</tr>
>>;
          line
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


          trips = vehicle{"trips"};

          trips_html = trips.map(format_trip_line).join(" ");	      

	  total_trips = vehicle{"tripTotals"};

	  trip_avgs = vehicle{"tripAverages"};
          avg_duration = (trip_avgs{"duration"} || 0).sprintf("%.0f");       
          avg_miles = trip_avgs{"miles"};
          avg_cost = trip_avgs{"cost"};

          fillups = vehicle{"fillups"};


	  total_fillups = vehicle{"fuelTotals"};

          no_fillups = <<
<tr>
 <td colspan="5" style="text-align:center;font-family:Arial, sans-serif;font-size:14px;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:#aaa;color:#333;background-color:#fff;">
  No fillups in the last week
 </td>
</tr>
>>;
          fillups_html = fillups.length() > 0 => fillups.map(format_fillup_line).join(" ")
                                               | no_fillups;



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
<tr>
 <td colspan="2" style="#{vehicle_table_row_style}">
  <span style="font-size:18px;font-weight:bold;margin-top:50px;">Trips</span>
 </td>
</tr>

<tr><td colspan="2" style="#{vehicle_table_row_style}"><b>#{name} took #{num_trips} trips: #{total_miles} miles, #{total_duration} min, $#{total_cost}</b></td></tr>
<tr><td colspan="2" style="#{vehicle_table_row_style}">Trip averages: #{avg_miles} miles, #{avg_duration} min, $#{avg_cost}</b></td></tr>

<tr><!-- trips -->
 <td colspan="2" style="#{vehicle_table_row_style}">
  <table class="trip" style="width:585px;border-collapse:collapse;border-spacing:0;border-color:#aaa;">
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

<tr>
 <td colspan="2" style="#{vehicle_table_row_style}">
  <span style="font-size:18px;font-weight:bold;margin-top:50px;">Fillups</span>
 </td>
</tr>

<tr><!-- fillups -->
 <td colspan="2" style="#{vehicle_table_row_style}">
  <table class="trip" style="width:585px;border-collapse:collapse;border-spacing:0;border-color:#aaa;">
   <tr>
    <tr>
    <td style="#{trip_table_header_style}">Date</td>
    <td style="#{trip_table_header_style}">Where</td>
    <td style="#{trip_table_header_style}">Gallons</td>
    <td style="#{trip_table_header_style}">Cost</td>
    <td style="#{trip_table_header_style}">MPG</td>
    </tr>
#{fillups_html} 

  </table>
 </td>
</tr><!-- fillups -->


</table><!-- vehicle "-->
>>;
          html
        }; // format_vehicle_summary

	mk_main_row = function(content) {
          row = <<
<tr>
 <td bgcolor="ffffff" style="padding-top: 15px;text-align:left;">
   #{content}
 </td>
</tr>	
>>;
          row
        };
	
	// turn it inside out: array of maps becomes map of arrays
        vehicle_html = fleet_details
                         .map(format_vehicle_summary)
			 .map(mk_main_row)
			 .join(" ");

        fleet_trip_totals = fleet_details
	                       .map(function(v){v{"tripTotals"}}).klog(">>>> array of trip totals: >>>> ")
	                       .reduce(add_maps);
        fleet_fillups_totals = fleet_details
  	                         .map(function(v){v{"fuelTotals"}})
	                         .reduce(add_maps);

	fleet_total_trip_num = fleet_trip_totals{"num"};
	fleet_total_trip_miles = fleet_trip_totals{"miles"}.sprintf("%.1f");
	fleet_total_trip_duration = fleet_trip_totals{"duration"}.sprintf("%.1f");
	fleet_total_trip_cost =fleet_trip_totals{"cost"}.sprintf("%.2f");
	fleet_total_fuel_num = fleet_fillups_totals{"num"};
	fleet_total_fuel_volume = fleet_fillups_totals{"volume"}.sprintf("%.1f");
	fleet_total_fuel_cost = fleet_fillups_totals{"cost"}.sprintf("%.2f");
	
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
 <td bgcolor="ffffff" style="text-align:center;">

 </td>
</tr>


<tr><td bgcolor="ffffff" style="font-size:18px;#{vehicle_table_row_style}"><b>Fleet totals:</b></td></tr>
<tr><td bgcolor="ffffff" style="#{vehicle_table_row_style}">Trips: #{fleet_total_trip_num} trips, #{fleet_total_trip_miles} miles, #{fleet_total_trip_duration} min, $#{fleet_total_trip_cost}</td></tr>
<tr><td bgcolor="ffffff" style="#{vehicle_table_row_style}">Fillups: #{fleet_total_fuel_num} fillups, #{fleet_total_fuel_volume} gal, $#{fleet_total_fuel_cost}</td></tr>



#{vehicle_html}


>>;
      emailBody(html)
    }
  }
}
// fuse_reports.krl