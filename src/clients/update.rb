# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2006-2012 Novell, Inc. All Rights Reserved.
#
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact Novell, Inc.
#
# To contact Novell about this file by physical or electronic mail, you may find
# current contact information at www.novell.com.
# ------------------------------------------------------------------------------

# File:	clients/update.ycp
# Module:	System update
# Summary:	Main update client
# Authors:	Klaus Kaempf <kkaempf@suse.de>
#		Arvin Schnell <arvin@suse.de>
#		Lukas Ocilka <locilka@suse.cz>
#
# $Id$
module Yast
  class UpdateClient < Client
    def main
      textdomain "update"

      Yast.import "GetInstArgs"
      Yast.import "CommandLine"
      Yast.import "Mode"

      # Bugzilla #269910, CommanLine "support"
      # argmap is only a map, CommandLine uses string parameters
      if Builtins.size(GetInstArgs.argmap) == 0 &&
          Ops.greater_than(Builtins.size(WFM.Args), 0)
        Mode.SetUI("commandline")
        Builtins.y2milestone("Mode CommandLine not supported, exiting...")
        # TRANSLATORS: error message - the module does not provide command line interface
        CommandLine.Print(
          _("There is no user interface available for this module.")
        )
        return :auto
      end

      Builtins.y2milestone("Running: run_update")
      @ret = Convert.to_symbol(WFM.CallFunction("run_update", WFM.Args))
      Builtins.y2milestone("Returned: %1", @ret)

      @ret
    end
  end
end

Yast::UpdateClient.new.main
