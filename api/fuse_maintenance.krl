ruleset fuse_maintenance {
  meta {
    name "Fuse Maintenance App"
    description <<
Operations for maintenance
    >>
    author "PJW"
    sharing on

    errors to b16x13

    use module b16x10 alias fuse_keys

    use module a169x625 alias CloudOS
    use module a169x676 alias pds
    use module b16x19 alias common
    use module b16x11 alias carvoyant
    use module b16x9 alias vehicle

	
    provides mileage
  }

  global {

    // external decls
    mileage = function(){
      1;
    };

  
  }


}
