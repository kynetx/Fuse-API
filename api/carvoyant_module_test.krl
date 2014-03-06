ruleset carvoyant_module_test {
  meta {
    name "Carvoyant module test"
    description <<
Test the Carvoyant module
>>
    author "Phil Windley"
    logging on
    
    use module b16x5 alias dropbox_keys

  }

  global {

    my_tokens = {'access_token' : ent:access_token || '',
              	 'access_token_secret' : ent: access_token_secret || ''
	     	};

    authorized = dropbox:is_authorized(my_tokens);

  }

  rule get_request_token_test { 
    select when test get_request_token

    pre {
      values = {'tokens' : my_tokens,
                'header' : dropbox:return_header(my_tokens)
               };
    }   

    if(not authorized) then {
      dropbox:get_request_token();	   
      show_test:diag("test initiation", values);
    }  

    always {
      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";
      log "Tokens: " + my_tokens.encode();
      log "Header: " + dropbox:return_header(my_tokens);
      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";
    }
  }

  rule process_request_token {
    select when http post label "request_token"
    pre {
      test_desc = <<
Checks to make sure we got request tokens back from Dropbox
>>;

      tokens = event:attr("status_code") eq '200' => dropbox:decode_content(event:attr('content')) | {};

      url = dropbox:generate_authorization_url(tokens{'oauth_token'} || 'NO_TOKEN');
      values = {'request_tokens' : tokens,
                'authorization_url' : url,
		'http_response' : event:attrs()
               };
    }
    if(not tokens{'oauth_token'}.isnull() && 
       not tokens{'oauth_token'}.isnull()) then {
      show_test:diag("processing request token", values);
    }
    fired {
      raise test event succeeds with
        test_desc = test_desc and
        rulename = meta:ruleName() and
	msg = "request tokens are defined" and
	details = values;

      set ent:request_token_secret tokens{'oauth_token_secret'};
      set ent:request_token tokens{'oauth_token'};
    } else {
      raise test event fails with
        test_desc = test_desc and
        rulename = meta:ruleName() and
	msg = "request tokens are empty" and
	details = values;

      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";
      log "Tokens: " + tokens.encode();
      log "Callback URL: " + url;
      log "Event attrs: " + event:attrs().encode();
      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";
      last;
    }
  }
 
  rule get_access_token {
    select when oauth response
    if(not authorized) then {
      dropbox:get_access_token(ent:request_token, ent:request_token_secret);
    }    
  }


  rule process_access_token {
    select when http post label "access_token"
    pre {
      tokens = dropbox:decode_content(event:attr('content'));
      url = "https://squaretag.com/app.html#!/app/#{meta:rid()}/show";
      js = <<
<html>
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <title></title>
  <META HTTP-EQUIV="Refresh" CONTENT="0;#{url}">
  <meta name="robots" content="noindex"/>
  <link rel="canonical" href="#{url}"/>
</head>
<body>
<p>
You are being redirected to <a href="#{url}">#{url}</a>
</p>
<script type="text/javascript">
window.location = #{url};
</script>

</body>
</html>
>>;
    }
    send_raw("text/html")
        with content= js
    always {
      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";
      log meta:ruleName() + " Tokens: " + tokens.encode();
      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";
      set ent:dropbox_uid tokens{'uid'};
      set ent:access_token_secret tokens{'oauth_token_secret'};
      set ent:access_token tokens{'oauth_token'};
      last;
    }
  }
 

  rule show_account_info { 
    select when web cloudAppSelected
    pre {
      
      account_info = dropbox:core_api_call('/account/info', my_tokens);
      name = account_info{'display_name'};
      uid = account_info{'uid'};

      metadata = dropbox:core_api_call('/metadata/sandbox/?list=true', my_tokens);
      files = metadata{'contents'}.isnull() => ""
                                             | metadata{'contents'}.map(function(x){x{'path'}}).join('<br/>');

      my_html = <<
<div style="margin: 0px 0px 20px 20px">
<p>Your Dropbox name is #{name} and your UID is #{uid}.</p>

<p>Files:<br/>#{files}</p>

</div>
>>;

  // <p>Token: #{ent:access_token}; Secret: #{ent:access_token_secret}</p>

    }
    if(authorized) then
    {
      CloudRain:createLoadPanel("Dropbox Account Info", {}, my_html);
    }

    fired {
      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";
      log meta:ruleName() + " Toens: " + my_tokens.encode();
      log "Account info: " + name + " " + "uid";
      log "files: " + files;
      log "<<<<<<<<<<<<<<<<<<<<<<<<<<<>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";
    }
  }

}