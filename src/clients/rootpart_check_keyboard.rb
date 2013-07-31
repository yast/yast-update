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

# Module:	rootpart_check_keyboard.ycp
#
# Author:	Lukas Ocilka <locilka@suse.cz>
#
# Purpose:	Break build-requires, used only in inst-sys
#
# $Id$
module Yast
  class RootpartCheckKeyboardClient < Client
    def main
      textdomain "update"

      Yast.import "Keyboard"
      Yast.import "GetInstArgs"
      Yast.import "Installation"

      @argmap = GetInstArgs.argmap
      Builtins.y2milestone("Script args: %1", @argmap)
      @destdir = Ops.get_string(@argmap, "destdir", Installation.destdir)

      Builtins.y2milestone(
        "Checking keyboard in system mounted to %1",
        @destdir
      )
      Keyboard.CheckKeyboardDuringUpdate(@destdir)

      true
    end
  end
end

Yast::RootpartCheckKeyboardClient.new.main
