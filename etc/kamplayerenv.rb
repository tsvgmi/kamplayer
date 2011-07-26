#---------------------------------------------------------------------------
# File:        toolenv.rb
# Date:        Thu Nov 22 18:45:57 -0500 2007
# Copyright:   Mocana, 2007
# Description: Bootstrap for MSS ruby scripts
# $Id: emtoolsenv.rb 3 2010-11-06 08:48:57Z tvuong $
#---------------------------------------------------------------------------
#+++
if !ENV['EM_TOOL_DIR']
  ["/etrade/tools", "#{ENV['HOME']}/etfw2"].each do |adir|
    if test(?d, adir)
      ENV["EM_TOOL_DIR"] = adir
      break
    end
  end
  raise "EM_TOOL_DIR not defined" uness ENV['EM_TOOL_DIR']
end
$: << ENV["EM_APP_DIR"] + "/lib"

require "#{ENV['EM_TOOL_DIR']}/lib/../etc/kamplayerenv"

