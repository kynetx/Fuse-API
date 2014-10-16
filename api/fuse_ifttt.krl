 ruleset fuse_ifttt {
  meta {
    name "Fuse IFTTT Test App"
    description <<
Playing with Fuse IFTTT channel
    >>
    author "PJW"
    sharing on

    errors to b16x13

    use module b16x10 alias fuse_keys

    use module a169x676 alias pds
    use module b16x19 alias common
	
    provides fart
  }

  global {

      fart = function() {5};



  }



}
// fuse_ifttt.krl
