ruleset fuse_common {
    meta {
        name "Fuse Common Decls"
        description <<
Common definitions
        >>
        author "PJW"

	provides S3Bucket, namespace
    }

    global {


      S3Bucket = function(){"k-fuse-01"};

      namespace = function(type) {
        meta_id = "fuse-meta";
	meta_id    
      };


    }

}
