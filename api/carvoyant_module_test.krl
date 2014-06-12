ruleset carvoyant_module_test {
  meta {
    name "Carvoyant module test"
    description <<
Test the Carvoyant module
>>
    author "Phil Windley"
    logging on

    errors to a16x13

    use module b503129x0 alias show_test

    use module b16x11 alias carvoyant

  }

  global {

  }

  // ---------- test configuration function ----------
  rule get_config_test { 
    select when test get_config

    pre {
      test_desc = <<
Checks to make sure get_config() works
>>;

      config = carvoyant:get_config(event:attr("vehicleID"));

      values = {'config_data' : config
               };


    }   

    if( config{"apiKey"} && config{"secToken"} ) then {
      show_test:diag("test get_config", values);
    }

    fired {
      raise test event use_config with 
        config_data = config;
      raise test event succeeds for b503129x0 with
        test_desc = test_desc and
        rulename = meta:ruleName() and
	msg = "config data is valid" and
	details = values;

    } else {
      raise test event fails for b503129x0 with
        test_desc = test_desc and
        rulename = meta:ruleName() and
	msg = "config data empty" and
	details = values;

      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";
      log "Config: " + config.encode();
      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";

    }
  }
 

  // ---------- test headers function ----------
  rule use_config_headers {
    select when test use_config
    pre {
      test_desc = <<
Check that headers are good
>>;

      config_data = event:attr("config_data");
      params = {
        "foo" : 1,
        "blah" : {"flip": "flop"}
      };
      headers = carvoyant:carvoyant_headers(config_data,params);

      values = {
        "config" : config_data,
        "params" : params,
        "headers" : headers
      };
    }
    if ( headers{["credentials", "username"]} eq config_data{"apiKey"}
      && headers{["params","blah","flip"]} eq "flop"
      ) then {
      show_test:diag("test check_header", values);
    }

    fired {
     raise test event succeeds for b503129x0 with
        test_desc = test_desc and
        rulename = meta:ruleName() and
	msg = "config data is valid" and
	details = values;
    } else {
      raise test event fails for b503129x0 with
        test_desc = test_desc and
        rulename = meta:ruleName() and
	msg = "config data empty" and
	details = values;
    }
  }

  // ---------- test vehicle data function ----------
  rule get_vehicle_data {
    select when test use_config
    pre {
      test_desc = <<
Check that get_vehicle() works
>>;

      vehicle_data = carvoyant:carvoyant_vehicle_data();
      vehicles = vehicle_data{"content"};

      values = {
        "vehicle_data" : vehicles
      };
    }
    if ( vehicle_data{"status_code"} eq "200"
      && vehicles{"vehicle"}.length() > 0
      ) then {
      show_test:diag("test carvoyant_vehicle_data", values);
    }

    fired {
     raise test event succeeds for b503129x0 with
        test_desc = test_desc and
        rulename = meta:ruleName() and
	msg = "vehicle data is valid" and
	details = values;
    } else {
      raise test event fails for b503129x0 with
        test_desc = test_desc and
        rulename = meta:ruleName() and
	msg = "vehicle data not valid" and
	details = values;
    }
  }

  // ---------- test subscriptions ----------
  rule getSubscription_test { 
    select when test getSubscription

    pre {
      test_desc = <<
Checks to make sure getSubscription() works
>>;

      vehicle_data = carvoyant:carvoyant_vehicle_data();
      vehicleId = carvoyant:get_vehicle_data(vehicle_data, 0, "vehicleId");

      subscriptions = carvoyant:getSubscription(vehicleId);

      values = {'subscription_data' : subscriptions,
                'vehicleId': vehicleId
	       };



    }   

    // expect an empty subscription back
    if( carvoyant:no_subscription(subscriptions) ) then {
      show_test:diag("test getSubscription empty", values);
    }

    fired {
      raise test event add_subscription with vehicleId = vehicleId;
      raise test event succeeds for b503129x0 with
        test_desc = test_desc and
        rulename = meta:ruleName() and
	msg = "initial subscription data is valid" and
	details = values;

    } else {
      raise test event del_subscription attributes subscriptions{"content"};
      raise test event fails for b503129x0 with
        test_desc = test_desc and
        rulename = meta:ruleName() and
	msg = "initial subscription data not valid" and
	details = values;

      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";
      log "Values: " + values.encode();
      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";

    }
  }
 


  rule add_subscription_init { 
    select when test add_subscription
    pre {
      test_desc = <<
Add a subscription and then raise an event to test that it's there
>>;
      vid = event:attr("vehicleId");
      values = {
        "vehicleId" : vid
      };
    }   
    // expect an empty subscription back
    {
      show_test:diag("initializing subscription test", values);
      carvoyant:add_subscription(vid, "lowBattery", {"minimumTime": "35"})
        with ar_label = "subscription_added";
    }
  }
 
  rule subscription_added_init {
    select when http post status_code re#(2\d\d)# label "subscription_added" setting (status)
    pre {
      test_desc = <<
Checks to make sure subscription was added by add_subscription()
>>;

      vehicle_data = carvoyant:carvoyant_vehicle_data();
      vehicleId = carvoyant:get_vehicle_data(vehicle_data, 0, "vehicleId");

      subscriptions = carvoyant:getSubscription(vehicleId);

      

      values = {'subscription_data' : subscriptions,
                'vehicleId': vehicleId,
		'data_from_subscription_action': event:attrs()
	       };


    }   

    if( subscriptions{"status_code"} eq "200" 
     && subscriptions{["content","subscriptions"]}
           .filter(function(s){s{"deletionTimestamp"}.isnull()})
	   .head()
	   .pick("$.._type") eq "LOWBATTERY"
      ) then {
      show_test:diag("getSubscription not empty", values);
    }

    fired {
      raise test event subscription_added attributes subscriptions{"content"};
      raise test event succeeds for b503129x0 with
        test_desc = test_desc and
        rulename = meta:ruleName() and
	msg = "subscription created" and
	details = values;

    } else {
      raise test event fails for b503129x0 with
        test_desc = test_desc and
        rulename = meta:ruleName() and
	msg = "subscription creation failed" and
	details = values;

      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";
      log "Values: " + values.encode();
      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";

    }
  }


  rule subscription_added_final {
    select when test subscription_added 
             or test del_subscription
    pre { 

     subscription = event:attr("subscriptions").filter(function(s){ s{"deletionTimestamp"}.isnull() }).head();
     // delete subscription and ensure it's gone. 

     values = {'subscription' : subscription,
               "attributes": event:attrs()
              };


    }   

    {
      carvoyant:del_subscription("lowBattery", subscription{"id"}, subscription{"vehicleId"})
        with ar_label = "subscription_deleted";
      show_test:diag("deleteing subscription", values);
    }
  }   

  rule subscription_deleted_check {
    select when http delete status_code re#(2\d\d)# label "subscription_deleted" setting (status)
    pre {
      test_desc = <<
Checks to make sure subscription was deleted by del_subscription()
>>;

      vehicle_data = carvoyant:carvoyant_vehicle_data();
      vehicleId = carvoyant:get_vehicle_data(vehicle_data, 0, "vehicleId");

      subscriptions = carvoyant:getSubscription(vehicleId);

      values = {'subscription_data' : subscriptions,
                'vehicleId': vehicleId
	       };

    }   

    // expect an empty subscription back
    if( carvoyant:no_subscription(subscriptions) ) then {
      show_test:diag("getSubscription is empty", values);
    }
    fired {
      raise test event succeeds for b503129x0 with
        test_desc = test_desc and
        rulename = meta:ruleName() and
	msg = "subscription deleted" and
	details = values;

    } else {
      raise test event fails for b503129x0 with
        test_desc = test_desc and
        rulename = meta:ruleName() and
	msg = "subscription deletion failed" and
	details = values;

      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";
      log "Values: " + values.encode();
      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";

    }
  }  


  rule add_subscription_failed {
    select when http post status_code re#([45]\d\d)# label "subscription_added" setting (status)
    pre {
      test_desc = <<
Failed to successfully add subscription
>>;

	values = event:attrs();

    }   

    // expect an empty subscription back
    {
      show_test:diag("add_subscrition action failed", values);
    }

    always {
      raise test event fails for b503129x0 with
        test_desc = test_desc and
        rulename = meta:ruleName() and
	msg = "add_subscription action failed" and
	details = values;

      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";
      log "Values: " + values.encode();
      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";

    }
  }

  // ---------- For error handling ----------
  // sets error handling check off
  rule test_handle_error_init {
    select when test handle_error
    always {
      raise system event error for b16x13 with 
       error_rid = meta:rid() and
       genus = "test" and
       species = "handle_error" and
       level = "warn" and
       msg = "test message" and
       _test = true
      
    }
  }

  rule test_handle_error { 
    select when test error_handled

    pre {
      test_desc = <<
Checks to make sure error handler ruleset fires
>>;

      rid = event:attr("rid");
      other = event:attr("attrs");

      values = {'attributes' : other
               };
    }   

    if( other{"error_rid"} eq meta:rid() 
     && other{"genus"} eq "test"
     && other{"species"} eq "handle_error"
     && other{"level"} eq "warn"
      ) then {
      show_test:diag("test error handling", values);
    }

    fired {
      raise test event succeeds for b503129x0 with
        test_desc = test_desc and
        rulename = meta:ruleName() and
	msg = "error data is valid" and
	details = values;

    } else {
      raise test event fails for b503129x0 with
        test_desc = test_desc and
        rulename = meta:ruleName() and
	msg = "error data is invalid" and
	details = values;

      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";
      log "Error attributes: " + other.encode();
      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";

    }
  }
 

  // ---------- test trip_info function ----------
  rule trip_info_test { 
    select when test trip_info

    pre {
      test_desc = <<
Checks to make sure trip_info() works
>>;

      vid = event:attr("vehicleId");
      tid = event:attr("tripId");
      trip = carvoyant:tripInfo(tid,vid);

      values = {
      	        'trip_id' : tid,
		'vehicle_id' : vid,
      	        'trip_data' : trip
               };


    }   

    if( trip{"mileage"} ) then {
      show_test:diag("test trip_info", values);
    }

    fired {
      raise test event succeeds for b503129x0 with
        test_desc = test_desc and
        rulename = meta:ruleName() and
	msg = "trip data is valid" and
	details = values;

    } else {
      raise test event fails for b503129x0 with
        test_desc = test_desc and
        rulename = meta:ruleName() and
	msg = "trip data empty" and
	details = values;

    }
  }
 


}