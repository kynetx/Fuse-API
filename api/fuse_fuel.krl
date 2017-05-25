 ruleset fuse_fuel {
  meta {
    name "Fuse Fuel App"
    description <<
Operations for fuel
    >>
    author "PJW"
    sharing on

    errors to b16x13

    use module b16x10 alias fuse_keys

    use module a169x676 alias pds
    use module b16x19 alias common
    use module b16x11 alias carvoyant

	
    provides fillups, fillupsByDate, currentCPM, standardMPG, standardCPG, callEdmunds, callFuelEconomy, exportFillups
  }

  global {

    // external decls
    fillupsByDate = function(start, end){

      utc_start = common:convertToUTC(start);
      utc_end = common:convertToUTC(end);

      sort_opt = {
        "path" : ["timestamp"],
	"reverse": true,
	"compare" : "datetime"
      };
      
      this2that:transform(ent:fuel_purchases.query([], { 
       'requires' : '$and',
       'conditions' : [
          { 
     	   'search_key' : [ 'timestamp'],
       	   'operator' : '$gte',
       	   'value' : utc_start 
	  },
     	  {
       	   'search_key' : [ 'timestamp' ],
       	   'operator' : '$lte',
       	   'value' : utc_end 
	  }
	]},
	"return_values"
	),
	sort_opt
      )
    }

    fillups = function(id, limit, offset) {
       // x_id = id.isnull().klog(">>>> id >>>>>");
       // x_limit = limit.klog(">>>> limit >>>>>");
       // x_offset = offset.klog(">>>> offset >>>>>"); 

      id.isnull() || id eq "" => allFillups(limit, offset)
                               | ent:fuel_purchases{id};
    };

    allFillups = function(limit, offset) {
      sort_opt = {
        "path" : ["timestamp"],
	"reverse": true,
	"compare" : "datetime"
      };

      max_returned = 25;

      hard_offset = offset.isnull() 
                 || offset eq ""        => 0               // default
                  |                        offset;

      hard_limit = limit.isnull() 
                || limit eq ""          => 10              // default
                 | limit > max_returned => max_returned
		 |                         limit; 

      global_opt = {
        "index" : hard_offset,
	"limit" : hard_limit
      }; 

      sorted_keys = this2that:transform(ent:fuel_purchases, sort_opt, global_opt.klog(">>>> transform using global options >>>> ")) || [];
      sorted_keys.map(function(id){ ent:fuel_purchases{id} })
    };

 // result; 
 // {
 // "cost": "24.29",
 // "volume": "15.682",
 // "mpg": "13.34",
 // "location": null,
 // "distance": "209.2",
 // "interval": 1009046,
 // "timestamp": "20160224T161726+0000",
 // "id": "17DCB874-DB12-11E5-A341-73F4E71C24E1",
 // "unit_price": "1.549",
 // "odometer": "92784.2"
 // },

    defaultMPG = 15;

    currentCPM = function() {
      fillup = fillups(null, 1, 0).head() || {};
      vehicle_mpg = not fillup{"mpg"}.isnull() => fillup{"mpg"} + 0 // ensure it's a number
                                                | standardMPG().defaultsTo(defaultMPG);
      vehicle_cpg = not fillup{"unit_price"}.isnull() => fillup{"unit_price"}  + 0
                                                       | standardCPG();

      mpg = vehicle_mpg => vehicle_mpg | defaultMPG; 
      cpg = vehicle_cpg.defaultsTo(0);

      cpm = cpg / mpg.klog(">>>> MPG value >>>>");
      {"costPerMile": cpm.defaultsTo(0),
       "mpg": mpg.klog(">>> MPG >>>>"),
       "costPerGallon": cpg.klog(">>> CPG >>>>"),
       "vehicleData": not fillup{"mpg"}.isnull() && not fillup{"unit_price"}.isnull()
      }.klog(">>>>> returning CPM >>>>>> ")
      
    };

    standardMPG = function() {
      not ent:mpg => callEdmunds()
                   | ent:mpg.klog(">>>> returning cached MPG >>>>") 
    }

    callEdmunds = function() {
      vin = pds:get_me("vin");
      edmunds_key = keys:edmunds_client("key").klog(">>> edmunds key >>>>");
      edmunds_url = "https://api.edmunds.com/api/vehicle/v2/vins/#{vin}";
      raw_resp = http:get(edmunds_url, {"fmt":"json",
                                        "api_key": edmunds_key});
      resp = raw_resp{"status_code"} eq "200" => raw_resp{"content"}.decode().klog(">>>> Edmunds response >>>> ")
                                               | {};
      highway = resp{["MPG","highway"]}.defaultsTo(defaultMPG);
      city = resp{["MPG","city"]}.defaultsTo(defaultMPG);
      mpg = (highway + city) / 2  // assume half city, half highway
      mpg.pset(ent:mpg); 
    }
      
    standardCPG = function() {
      num_days = 2;
      expired = (ent:cpg{"timestamp"} + (num_days * 3600 * 24) < time:strftime(time:now(), "%s")).klog(">>> cpg expired? >>>>");
      result = not ent:cpg || expired => callFuelEconomy()
                                       | ent:cpg.klog(">>>> returning cached CPG >>>>") ;
      result{"cpg"}
    }

    callFuelEconomy = function() {
      fe_url = "http://www.fueleconomy.gov/ws/rest/fuelprices"; 
      raw_resp = http:get(fe_url);
      resp = raw_resp{"status_code"} eq "200" => raw_resp{"content"}
                                               | "<nodata></nodata>";
      json = (this2that:xml2json(resp, {"content_key" : "val"}).decode() || {}).klog(">>>> response as JSON >>>> ");
      cpg = json{["fuelPrices", "midgrade", "val"]} || "3.50";
      cpg_obj = {"cpg" : cpg,
                 "timestamp": time:strftime(time:now(), "%s")
                };
      cpg_obj.pset(ent:cpg);   
    }


 // result; 
 // {
 // "cost": "24.29",
 // "volume": "15.682",
 // "mpg": "13.34",
 // "location": null,
 // "distance": "209.2",
 // "interval": 1009046,
 // "timestamp": "20160224T161726+0000",
 // "id": "17DCB874-DB12-11E5-A341-73F4E71C24E1",
 // "unit_price": "1.549",
 // "odometer": "92784.2"
 // },
    exportFillups = function(start, end, tz) {
      timezone = tz.defaultsTo("America/Denver"); 

      fillups = fillupsByDate(start,end)
                 .map(function(v){ v.put(["date"], time:strftime(v{"timestamp"},"%F", {"tz":timezone}))
				                            .put(["time"], time:strftime(v{"timestamp"},"%r", {"tz":timezone}))
		                 });

      // order fields
      field_array = ["id", "date", "time", "cost", "volume", "mpg", "distance", "unit_price", "odometer", "location"
                    ];

      csv:from_array(fillups, field_array);
    }

      
  }


  rule record_fuel_purchase {
    select when fuse new_fuel_purchase
    pre {
      rec = event:attrs()
              .delete(["id"]) // new records can't have id
	      ; 
    }      
    {
      send_directive("Recording fill up") with rec = rec
    }
    fired {
      raise fuse event updated_fuel_purchase attributes rec; // Keeping it DRY
    }
  }

  rule update_fuel_purchase {
    select when fuse updated_fuel_purchase
    pre {

      // if no id, assume new record and create one
      new_record = event:attr("id").isnull();
      current_time = common:convertToUTC(time:now());

      id = event:attr("id") || random:uuid();  // UTC; using time as id

      vdata = common:vehicleSummary();

      volume = event:attr("volume").defaultsTo(1.0);
      unit_price = event:attr("unitPrice");
      odometer = event:attr("odometer") || vdata{"mileage"};
      location = event:attr("location");
      
      offset = new_record => 0 | 1; // new record isn't already on the list
      lastfillup = fillups(null, 1, offset).head().klog(">>>> returned from fillup >>>> ") || {};
      distance = lastfillup{"odometer"}.isnull() => 0 | (odometer - lastfillup{"odometer"});
      mpg = distance/volume;

      when_bought = common:convertToUTC(event:attr("when") || time:now());

      seconds = lastfillup{"timestamp"}.isnull() => 0 | (time:strftime(when_bought, "%s") - time:strftime(lastfillup{"timestamp"}, "%s"));

      cost = volume * unit_price;


      rec = {
        "id": id,	    
        "volume": volume,
	"unit_price": unit_price,
	"cost": cost.sprintf("%.2f"),
	"location": location,
	"odometer": odometer.sprintf("%.1f"),
	"distance": distance.sprintf("%.1f"),
	"mpg": (mpg < 100) => mpg.sprintf("%.2f") // throw out bad data
	                    | 0,
	"interval": seconds,
	"timestamp": when_bought
      };
    }
    if( not volume.isnull() 
     && not unit_price.isnull()
     && not odometer.isnull()
     && not id.isnull()
      ) then
    {
      send_directive("Updating fill up") with
        rec = rec
    }
    fired {
       // raise pds event new_data_available
       //   attributes {
       // 	    "namespace": common:fuel_namespace(),
       // 	    "keyvalue": id,
       // 	    "value": rec,
       //       "_api": "sky"
 		   
       // 	  };
      log(">>>>>> Storing fuel purchase >>>>>> " + rec.encode());
      set ent:fuel_purchases{id} rec;
      raise fuse event fuel_purchase_saved;
    } else {
      log(">>>>>> Could not store fuel record " + rec.encode());
    }
  }

  rule delete_fuel_purchase {
    select when fuse unneeded_fuel_purchase
    pre {
      id = event:attr("id");
    }
    if( not id.isnull() 
      ) then
    {
      send_directive("Deleting fill up") with
        rec = rec
    }
    fired {
       // raise pds event remove_old_data
       //   attributes {
       // 	    "namespace": common:fuel_namespace(),
       // 	    "keyvalue": id,
       //       "_api": "sky"
 		   
       // 	  };
      raise fuse event fuel_purchase_deleted;
      clear ent:fuel_purchases{id};
    }
  }


  rule update_vehicle_totals {
    select when fuse fuel_purchase_saved
             or fuse fuel_purchase_deleted
    pre {

      // do current month if no month given
      raw_month = event:attr("month") || time:now();
      month = time:strftime(raw_month, "%m");
      year = time:strftime(raw_month, "%Y");

      start = time:strftime(raw_month, "%Y%m01T000000%z");
      end = time:add(start, {"months": 1});
      month_totals = fillupsByDate(start, end)
                      .reduce(function(a, b){ 
	                                      {"cost": a{"cost"} + b{"cost"}, 
		                               "distance": a{"distance"} + b{"distance"},
					       "volume": a{"volume"} + b{"volume"},
					       "fillups": a{"fillups"} + 1
					      }
					    },
			      {"cost": 0, 
			       "distance": 0,
			       "volume": 0,
			       "fillups": 0
			      }
                             );

    }
    {send_directive("Updated fuel summary for #{month}/#{year}") with
       values =  month_totals;
     event:send({"cid": common:fleetChannel()}, "fuse", "updated_vehicle") with
        attrs = {"keyvalue": "fuel_summaries,Y#{year},M#{month}",
	         "value": month_totals.encode()
	        };
      }

    always {
      set ent:monthly_fuel_summary{[year, month]} month_totals;
    }
  }

  rule send_fuel_export {
    select when fuse fuel_export
    pre {

      // configurables
      year = event:attr("year");
      month = event:attr("month");
      tz = event:attr("timezone").klog(">>> owner told me their timezone >>>> ").defaultsTo("America/Denver");


      profile = pds:get_all_me().defaultsTo({});
      vehicle_name = profile{"myProfileName"};

      subj = "Fuse Trip Export for #{vehicle_name} (#{month}/#{year})";

      tz_str = time:strftime(time:now({"tz": tz}), "%Y%m%dT%H%M%S%z")
                  .split(re/[+-]/)
                  .reverse()
                  .head()
                  .klog(">>>> tz string >>>>>>>")
                  ;
      start = time:new(year+month+"01T000000-"+tz_str);
      end = time:add(start, {"months": 1});


      // don't generate report unless there are vehicles
      csv = exportTrips(start, end, tz);

      msg = <<
Here is your trip export for #{vehicle_name} for #{month}/#{year}
      >>; 


      email_map = { "subj" :  subj, 
		    "msg" : msg,
		    "attachment": csv,
		    "filename" : "Trips_#{vehicle_name}_#{year}_#{month}.csv"
                  };


    }
    if(not csv.isnull() ) then
    {
      send_directive("sending email to fleet owner") with
        content = email_map;
    }
    fired {
      raise fuse event email_for_owner attributes email_map;
    }
    
  }


}
// fuse_fuel.krl
