ruleset carvoyant_module_test {
  meta {
    name "Carvoyant module test"
    description <<
Test the Carvoyant module
>>
    author "Phil Windley"
    logging on

    errors to a16x13

    use module b16x10 alias fuse_keys

    use module b503129x0 alias show_test

    use module b16x11 alias carvoyant

  }

  global {


  }

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
 

}