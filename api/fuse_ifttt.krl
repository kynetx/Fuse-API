 ruleset fuse_ifttt {
  meta {
    name "Fuse IFTTT Test App"
    description <<
Playing with Fuse IFTTT channel
    >>
    author "PJW"
    sharing on

    errors to b16x13

    // use module b16x10 alias fuse_keys

    use module a169x676 alias pds
    use module b16x19 alias common
	
    provides router
  }

  global {

      process_path = function() {
        path = meta:uri().klog(">>> seeing this path >>> ");
	path.extract(re#/event/[^/]+/[^/]+/[^/]+/[^/]+/(.*)$#).head().split(re#/#).klog(">>> returning these ops")
      };

  }

  rule router {
    select when fuse ifttt_incoming
    pre {
      ops_array = process_path();
      op1 = ops_array[2];
      op2 = ops_array[3];

      body = op1 eq "status" => {}
                              | {}
    }
    { send_raw("application/json") with
       content = body
    }


  }


}
// fuse_ifttt.krl
