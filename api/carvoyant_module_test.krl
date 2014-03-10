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

    if(not config{"apiKey"} ) then {
      show_test:diag("test get_config", values);
    }

    fired {
      raise test event succeeds for b503129x0 with
        test_desc = test_desc and
        rulename = meta:ruleName() and
	msg = "config data is valid" and
	details = values;

      set ent:request_token_secret tokens{'oauth_token_secret'};
      set ent:request_token tokens{'oauth_token'};
    } else {
      raise test event fails for b503129x0 with
        test_desc = test_desc and
        rulename = meta:ruleName() and
	msg = "config data empty" and
	details = values;

      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";
      log "Config: " + config;
      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";

    }
  }
 

}