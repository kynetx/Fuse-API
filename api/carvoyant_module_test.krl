ruleset carvoyant_module_test {
  meta {
    name "Carvoyant module test"
    description <<
Test the Carvoyant module
>>
    author "Phil Windley"
    logging on
    

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
 

  // sets it off
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

      passed = event:attr("details").pick("$..attrs");

      values = {'attributes' : event:attrs()
               };
    }   

    if( passed{"error_rid"} eq meta:rid() 
     && passed{"genus"} eq "test"
     && passed{"species"} eq "handle_error"
     && passed{"level"} eq "warn"
      ) then {
      show_test:diag("test error handling", values);
    }

    fired {
      raise test event succeeds for b503129x0 with
        test_desc = test_desc and
        rulename = meta:ruleName() and
	msg = "erro data is valid" and
	details = values;

    } else {
      raise test event fails for b503129x0 with
        test_desc = test_desc and
        rulename = meta:ruleName() and
	msg = "error data is invalid" and
	details = values;

      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";
      log "Error attributes: " + passed.encode();
      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";

    }
  }
 

}