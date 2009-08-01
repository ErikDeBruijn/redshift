# Process the selected libname or the name of the current program into
# an acceptable library name.
begin
  clib_name = ($REDSHIFT_CLIB_NAME || $0).dup
  clib_name =
    if clib_name == "\000PWD"  # irb in ruby 1.6.5 bug
      "irb"
    else
      File.basename(clib_name)
    end
  clib_name.sub!(/\.rb$/, '')
  clib_name.gsub!(/-/, '_')
  clib_name.sub!(/^(?=\d)/, '_')
    # other symbols will be caught in CGenerator::Library#initialize.
  clib_name << '_clib'
  $REDSHIFT_CLIB_NAME = clib_name
end

$REDSHIFT_WORK_DIR ||= "tmp"

if false ### $REDSHIFT_SKIP_BUILD
  # useful for: turnkey; fast start if no changes; manual lib edits
  f = File.join($REDSHIFT_WORK_DIR, $REDSHIFT_CLIB_NAME, $REDSHIFT_CLIB_NAME)
  require f
else
  require 'redshift/target/c/library'
  require 'redshift/target/c/flow-gen'
  require 'redshift/target/c/component-gen'
  require 'redshift/target/c/world-gen'
  
  RedShift.do_library_calls(RedShift.library)
end
