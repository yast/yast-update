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

# Module:		Update.ycp
#
# Authors:		Anas Nashif <nashif@suse.de>
#			Arvin Schnell <arvin@suse.de>
#			Lukas Ocilka <locilka@suse.cz>
#
# Purpose:		Update module
#
# $Id$
require "yast"

module Yast
  class UpdateClass < Module
    def main
      Yast.import "Pkg"

      textdomain "update"

      Yast.import "Installation"
      Yast.import "Packages"
      Yast.import "ProductFeatures"
      Yast.import "ProductControl"
      Yast.import "Stage"
      Yast.import "OSRelease"
      Yast.import "Mode"

      # number of packages to install
      @packages_to_install = 0

      # number of packages to update
      @packages_to_update = 0

      # number of packages to remove
      @packages_to_remove = 0

      # number of packages unknown (problematic) by update
      @unknown_packages = 0

      # number of errors (packages?) returned by solver
      @solve_errors = 0

      #    // Flag is set true if the user decides to delete unmaintained packages
      #    global boolean deleteOldPackages = nil;

      # Flag is set to true when package downgrade is allowed
      @silentlyDowngradePackages = nil

      # Flag is set to true if installed packages should be kept
      @keepInstalledPatches = nil

      # don't allow upgrade only update
      @disallow_upgrade = false

      @did_init1 = false

      @did_init2 = false

      @last_runlevel = -1

      # Only an update, NOT an upgrade
      @onlyUpdateInstalled = nil

      @selected_selection = ""

      @products_incompatible = false

      # Version of the targetsystem
      #
      # !!! moved to Installation::installedVersion !!!
      #
      # global map <string, any> installedVersion = $[];

      # Version of the source medium
      #
      # !!! moved to Installation::updateVersion !!!
      #
      # global map <string, any> updateVersion = $[];


      # Flag, if the basesystem have to be installed
      @updateBasePackages = false

      # counter for installed packages
      @packagesInstalled = 0


      # see bug #40358
      @manual_interaction = false

      # are the products (installed and to update) compatible?
      @_products_compatible = nil
    end

    #-----------------------------------------------------------------------
    # FATE #301844 - Tuning Update Features
    #-----------------------------------------------------------------------

    def ListOfRegexpsMatchesProduct(regexp_items, product)
      regexp_items = deep_copy(regexp_items)
      return false if regexp_items == nil || regexp_items == []
      if product == nil
        Builtins.y2error("Product is nil")
        return false
      end

      ret = false
      Builtins.foreach(regexp_items) do |one_regexp|
        if Builtins.regexpmatch(product, one_regexp)
          Builtins.y2milestone(">%1< is matching >%2<", product, one_regexp)
          ret = true
          raise Break
        end
      end

      Builtins.y2milestone("Returning %1", ret)
      ret
    end

    # Returns whether upgrade process should only update installed packages or
    # also install new packages. True means - do not upgrade, only update packages.
    # (Functionality for FATE #301844).
    def OnlyUpdateInstalled
      # changes onlyUpdateInstalled variable
      default_ous_a = ProductFeatures.GetFeature(
        "software",
        "only_update_selected"
      )

      default_ous = nil
      if default_ous_a == nil || default_ous_a == ""
        Builtins.y2error("software/only_update_selected not defined")
        return false
      end
      if Ops.is_boolean?(default_ous_a)
        default_ous = Convert.to_boolean(default_ous_a)
      end

      installed_system = OSRelease.ReleaseInformation(Installation.destdir)
      Builtins.y2milestone(
        "Processing '%1' from '%2'",
        installed_system,
        Installation.destdir
      )

      if installed_system == nil || installed_system == ""
        Builtins.y2error("Cannot find out installed system name")
        return default_ous
      end

      reverse_ous_a = ProductFeatures.GetFeature(
        "software",
        "only_update_selected_reverse_list"
      )
      # No reverse rules defined
      return default_ous if reverse_ous_a == ""
      # not a list or empty list
      reverse_ous = Convert.convert(
        reverse_ous_a,
        :from => "any",
        :to   => "list <string>"
      )
      return default_ous if reverse_ous == nil || reverse_ous == []

      if ListOfRegexpsMatchesProduct(reverse_ous, installed_system)
        return !default_ous
      end

      default_ous
    end

    # Returns whether upgrade process should silently downgrade packages if needed.
    # 'true' means that packages might be downgraded, 'nil' is returned when
    # the feature is not supported in the control file.
    def SilentlyDowngradePackages
      # returns empty string if not defined, buggy GetBooleanFeature
      default_sdp_a = ProductFeatures.GetFeature(
        "software",
        "silently_downgrade_packages"
      )

      default_sdp = nil
      if default_sdp_a == nil || default_sdp_a == ""
        Builtins.y2milestone("software/silently_downgrade_packages not defined")
        return nil
      end
      if Ops.is_boolean?(default_sdp_a)
        default_sdp = Convert.to_boolean(default_sdp_a)
      end

      installed_system = OSRelease.ReleaseInformation(Installation.destdir)
      Builtins.y2milestone(
        "Processing '%1' from '%2'",
        installed_system,
        Installation.destdir
      )

      if installed_system == nil || installed_system == ""
        Builtins.y2error("Cannot find out installed system name")
        return default_sdp
      end

      reverse_sdp_a = ProductFeatures.GetFeature(
        "software",
        "silently_downgrade_packages_reverse_list"
      )
      # No reverse rules defined
      return default_sdp if reverse_sdp_a == ""
      # not a list or empty list
      reverse_sdp = Convert.convert(
        reverse_sdp_a,
        :from => "any",
        :to   => "list <string>"
      )
      return default_sdp if reverse_sdp == nil || reverse_sdp == []

      if ListOfRegexpsMatchesProduct(reverse_sdp, installed_system)
        return !default_sdp
      end

      default_sdp
    end

    # Returns whether the installed product is supported for upgrade.
    # (Functionality for FATE #301844).
    def IsProductSupportedForUpgrade
      installed_system = OSRelease.ReleaseInformation(Installation.destdir)
      Builtins.y2milestone(
        "Processing '%1' from '%2'",
        installed_system,
        Installation.destdir
      )

      if installed_system == nil || installed_system == ""
        Builtins.y2error("Cannot find out installed system name")
        return false
      end

      supported_products_a = ProductFeatures.GetFeature(
        "software",
        "products_supported_for_upgrade"
      )
      # No products defined
      if supported_products_a == ""
        Builtins.y2warning("No products_supported_for_upgrade defined")
        return true
      end
      # not a list or empty list
      supported_products = Convert.convert(
        supported_products_a,
        :from => "any",
        :to   => "list <string>"
      )
      return true if supported_products == nil || supported_products == []

      if ListOfRegexpsMatchesProduct(supported_products, installed_system)
        return true
      end

      false
    end


    #-----------------------------------------------------------------------
    # GLOBAL FUNCTIONS
    #-----------------------------------------------------------------------


    def SelectedProducts
      selected = Pkg.ResolvableProperties("", :product, "")
      selected = Builtins.filter(selected) do |p|
        Ops.get(p, "status") == :selected
      end
      Builtins.maplist(selected) do |p|
        Ops.get_locale(
          p,
          "display_name",
          Ops.get_locale(
            p,
            "summary",
            Ops.get_locale(
              p,
              "name",
              Ops.get_locale(p, "version", _("Unknown Product"))
            )
          )
        )
      end
    end

    # Check if installed product and product to upgrade to are compatible
    # @return [Boolean] true if update is possible
    def ProductsCompatible
      if @_products_compatible == nil
        if Stage.normal
          # check if name of one of the products on the installation
          # media is same as one of the installed products
          # assuming that multiple products on installation media
          # are compatible and compatibility is transitive
          inst = Pkg.ResolvableProperties("", :product, "")
          inst = Builtins.filter(inst) { |p| Ops.get(p, "status") == :installed }
          inst_names = Builtins.maplist(inst) do |p|
            Ops.get_string(p, "name", "")
          end
          to_install = Builtins.maplist(Pkg.SourceGetCurrent(true)) do |src|
            prod_info = Pkg.SourceProductData(src)
            Ops.get_string(prod_info, "name", "")
          end
          # filter out empty products
          to_install = Builtins.filter(to_install) { |o_p| o_p != "" }

          Builtins.y2milestone("Installed products: %1", inst_names)
          Builtins.y2milestone("Products on installation media: %1", to_install)

          # at least one product name found
          if Ops.greater_than(Builtins.size(to_install), 0)
            equal_product = Builtins.find(inst_names) do |i|
              found = Builtins.find(to_install) { |u| u == i }
              found != nil
            end
            @_products_compatible = equal_product != nil 
            # no product name found
            # bugzilla #218720, valid without testing according to comment #10
          else
            Builtins.y2warning(
              "No products found, setting product-compatible to 'true'"
            )
            @_products_compatible = true
          end
        else
          @_products_compatible = true # FIXME this is temporary
        end
        Builtins.y2milestone(
          "Products found compatible: %1",
          @_products_compatible
        )
      end

      @_products_compatible
    end

    def IgnoreProductCompatibility
      @_products_compatible = true

      nil
    end

    # Set initial values for variables that user can't change.
    # They are defined in the control file.
    def InitUpdate
      Builtins.y2milestone("Calling: InitUpdate()")

      @silentlyDowngradePackages = SilentlyDowngradePackages()
      Builtins.y2milestone(
        "silentlyDowngradePackages: %1",
        @silentlyDowngradePackages
      )

      nil
    end

    # Drops packages defined in control file (string) software->dropped_packages
    #
    # @see bnc #300540
    def DropObsoletePackages
      packages_to_drop = ProductFeatures.GetStringFeature(
        "software",
        "dropped_packages"
      )

      if packages_to_drop == nil || packages_to_drop == ""
        Builtins.y2milestone("No obsolete packages to drop")
        return
      end

      l_packages_to_drop = Builtins.splitstring(packages_to_drop, ", \n")
      Builtins.y2milestone("Packages to drop: %1", l_packages_to_drop)

      Builtins.foreach(l_packages_to_drop) do |one_package|
        if Pkg.PkgInstalled(one_package) || Pkg.IsSelected(one_package)
          Builtins.y2milestone("Package to delete: %1", one_package)
          Pkg.PkgDelete(one_package)
        end
      end

      nil
    end

    #
    def Reset
      Builtins.y2milestone("Calling: UpdateReset()")

      InitUpdate()

      #	deleteOldPackages = DeleteOldPackages();
      #	y2milestone ("deleteOldPackages %1", deleteOldPackages);

      @onlyUpdateInstalled = OnlyUpdateInstalled()
      Builtins.y2milestone("onlyUpdateInstalled %1", @onlyUpdateInstalled)

      @disallow_upgrade = false

      @manual_interaction = false
      @products_incompatible = false
      @_products_compatible = nil

      Installation.update_backup_modified = true
      Installation.update_backup_sysconfig = true
      Installation.update_remove_old_backups = false
      Installation.update_backup_path = "/var/adm/backup"

      nil
    end


    #
    def fill_version_map(data)
      if Ops.get_string(data.value, "name", "?") == "?" &&
          Ops.get_string(data.value, "version", "?") == "?"
        Ops.set(data.value, "nameandversion", "?")
      else
        Ops.set(
          data.value,
          "nameandversion",
          Ops.add(
            Ops.add(Ops.get_string(data.value, "name", "?"), " "),
            Ops.get_string(data.value, "version", "?")
          )
        )
      end

      tmp0 = []
      if Builtins.regexpmatch(Ops.get_string(data.value, "version", ""), " -")
        Builtins.splitstring(Ops.get_string(data.value, "version", ""), " -")
      end

      tmp1 = []
      if Builtins.regexpmatch(Ops.get(tmp0, 0, ""), ".")
        Builtins.splitstring(Ops.get(tmp0, 0, ""), ".")
      end

      tmp2 = Builtins.tointeger(Ops.get(tmp1, 0, "-1"))
      Ops.set(data.value, "major", tmp2) if Ops.greater_or_equal(tmp2, 0)

      tmp3 = Builtins.tointeger(Ops.get(tmp1, 1, "-1"))
      Ops.set(data.value, "minor", tmp3) if Ops.greater_or_equal(tmp3, 0)

      nil
    end


    # Read product name and version for the old and new release.
    # Fill Installation::installedVersion and Installation::updateVersion.
    # @return success
    def GetProductName
      Installation.installedVersion = {}
      Installation.updateVersion = {}

      # get old product name

      # cannot use product information from package manager
      # for pre-zypp products
      # #153576
      old_name = OSRelease.ReleaseInformation(Installation.destdir)
      Builtins.y2milestone("OSRelease::ReleaseInformation: %1", old_name)

      # Remove 'Beta...' from product release
      if Builtins.regexpmatch(old_name, "Beta")
        old_name = Builtins.regexpsub(old_name, "^(.*)[ \t]+Beta.*$", "\\1") 
        # Remove 'Alpha...' from product release
      elsif Builtins.regexpmatch(old_name, "Alpha")
        old_name = Builtins.regexpsub(old_name, "^(.*)[ \t]+Alpha.*$", "\\1")
      end

      p = Builtins.findlastof(old_name, " ")
      if p == nil
        Builtins.y2error("release info <%1> is screwed", old_name)
        Installation.installedVersion = {}
      else
        Ops.set(Installation.installedVersion, "show", old_name)
        Ops.set(
          Installation.installedVersion,
          "name",
          Builtins.substring(old_name, 0, p)
        )
        Ops.set(
          Installation.installedVersion,
          "version",
          Builtins.substring(old_name, Ops.add(p, 1))
        )
        installedVersion_ref = arg_ref(Installation.installedVersion)
        fill_version_map(installedVersion_ref)
        Installation.installedVersion = installedVersion_ref.value
      end

      # "minor" and "major" version keys
      # bug #153576, "version" == "9" or "10.1" or ...
      inst_ver = Ops.get_string(Installation.installedVersion, "version", "")
      if inst_ver != "" && inst_ver != nil
        # SLE, SLD, OES...
        if Builtins.regexpmatch(inst_ver, "^[0123456789]+$")
          Ops.set(
            Installation.installedVersion,
            "major",
            Builtins.tointeger(inst_ver)
          ) 
          # openSUSE
        elsif Builtins.regexpmatch(inst_ver, "^[0123456789]+.[0123456789]+$")
          Ops.set(
            Installation.installedVersion,
            "major",
            Builtins.tointeger(
              Builtins.regexpsub(
                inst_ver,
                "^([0123456789]+).[0123456789]+$",
                "\\1"
              )
            )
          )
          Ops.set(
            Installation.installedVersion,
            "minor",
            Builtins.tointeger(
              Builtins.regexpsub(
                inst_ver,
                "^[0123456789]+.([0123456789]+)$",
                "\\1"
              )
            )
          )
        else
          Builtins.y2error("Cannot find out major/minor from >%1<", inst_ver)
        end
      else
        Builtins.y2error(
          "Cannot find out version: %1",
          Installation.installedVersion
        )
      end

      if Mode.test
        Builtins.y2error("Skipping detection of new system")
        return true
      end

      # get new product name

      num = Builtins.size(Packages.theSources)

      if Ops.less_or_equal(num, 0)
        Builtins.y2error("No source")
        Ops.set(Installation.updateVersion, "name", "?")
        Ops.set(Installation.updateVersion, "version", "?")
        updateVersion_ref = arg_ref(Installation.updateVersion)
        fill_version_map(updateVersion_ref)
        Installation.updateVersion = updateVersion_ref.value
        return false
      end

      update_to_source = nil
      Builtins.y2milestone("Known sources: %1", Packages.theSources)

      # So-called System Update
      Builtins.foreach(Packages.theSources) do |source_id|
        source_map = Pkg.SourceProductData(source_id)
        # source need to be described
        if source_map != {}
          if Ops.get_string(source_map, "productversion", "A") ==
              Ops.get_string(Installation.installedVersion, "version", "B")
            Builtins.y2milestone("Found matching product: %1", source_map)
            update_to_source = source_id
          else
            Builtins.y2error("Found non-matching product: %1", source_map)
            # every invalid product is selected
            update_to_source = source_id if update_to_source == nil
          end
        end
      end if Stage.normal(
      )

      # fallback for Stage::normal()
      if Stage.normal
        if update_to_source == nil
          update_to_source = Ops.get(
            Packages.theSources,
            Ops.subtract(num, 1),
            0
          )
        end 
        # default for !Stage::normal
      else
        update_to_source = Packages.GetBaseSourceID
      end

      new_product = Pkg.SourceProductData(update_to_source)
      new_source = Pkg.SourceGeneralData(update_to_source)

      Builtins.y2milestone(
        "Product to update to: %1 %2 %3",
        update_to_source,
        new_product,
        new_source
      )

      if new_product == nil
        Ops.set(Installation.updateVersion, "name", "?")
        Ops.set(Installation.updateVersion, "version", "?")
        Builtins.y2error(
          "Cannot find out source details: %1",
          Installation.updateVersion
        )
        updateVersion_ref = arg_ref(Installation.updateVersion)
        fill_version_map(updateVersion_ref)
        Installation.updateVersion = updateVersion_ref.value
        return false
      end

      # bugzilla #225256, use "label" first, then a "productname"
      Ops.set(Installation.updateVersion, "show", Ops.get(new_product, "label"))
      if Ops.get(Installation.updateVersion, "show") == nil
        Builtins.y2warning("No 'label' defined in product")

        if Ops.get_string(new_product, "productname", "?") == "?" &&
            Ops.get_string(new_product, "productversion", "?") == "?"
          Ops.set(Installation.updateVersion, "show", "?")
        else
          Ops.set(
            Installation.updateVersion,
            "show",
            Ops.add(
              Ops.add(Ops.get_string(new_product, "productname", "?"), " "),
              Ops.get_string(new_product, "productversion", "?")
            )
          )
        end
      end
      Ops.set(
        Installation.updateVersion,
        "name",
        Ops.get_string(
          new_product,
          "label",
          Ops.get_string(new_product, "productname", "?")
        )
      )
      Ops.set(
        Installation.updateVersion,
        "version",
        Ops.get_string(new_product, "productversion", "?")
      )
      updateVersion_ref = arg_ref(Installation.updateVersion)
      fill_version_map(updateVersion_ref)
      Installation.updateVersion = updateVersion_ref.value

      new_ver = Ops.get_string(Installation.updateVersion, "version", "")
      if new_ver != "" && new_ver != nil
        # SLE, SLD, OES...
        if Builtins.regexpmatch(new_ver, "^[0123456789]+$")
          Ops.set(
            Installation.updateVersion,
            "major",
            Builtins.tointeger(new_ver)
          ) 
          # openSUSE
        elsif Builtins.regexpmatch(new_ver, "^[0123456789]+.[0123456789]$")
          Ops.set(
            Installation.updateVersion,
            "major",
            Builtins.tointeger(
              Builtins.regexpsub(
                new_ver,
                "^([0123456789]+).[0123456789]$",
                "\\1"
              )
            )
          )
          Ops.set(
            Installation.updateVersion,
            "minor",
            Builtins.tointeger(
              Builtins.regexpsub(
                new_ver,
                "^[0123456789]+.([0123456789])$",
                "\\1"
              )
            )
          )
        else
          Builtins.y2error("Cannot find out major/minor from %1", new_ver)
        end
      else
        Builtins.y2error(
          "Cannot find out version: %1",
          Installation.updateVersion
        )
      end

      Builtins.y2milestone(
        "update from %1 to %2",
        Installation.installedVersion,
        Installation.updateVersion
      )

      true
    end

    def GetBasePatterns
      # get available base patterns
      patterns = Pkg.ResolvableProperties("", :pattern, "")
      patterns = Builtins.filter(patterns) do |p|
        if Ops.get(p, "status") != :selected &&
            Ops.get(p, "status") != :available
          next false
        end
        # if type != base
        true
      end
      Builtins.maplist(patterns) { |p| Ops.get_string(p, "name", "") }
    end


    def ReadInstalledDesktop
      SCR.Execute(
        path(".target.bash"),
        "/bin/mv -f /etc/sysconfig/windowmanager /etc/sysconfig/windowmanager.old"
      )
      SCR.Execute(
        path(".target.bash"),
        "/bin/ln -s /mnt/etc/sysconfig/windowmanager /etc/sysconfig/windowmanager"
      )
      ret = Convert.to_string(
        SCR.Read(path(".sysconfig.windowmanager.DEFAULT_WM"))
      )
      SCR.Execute(
        path(".target.bash"),
        "/bin/rm -f /etc/sysconfig/windowmanager"
      )
      SCR.Execute(
        path(".target.bash"),
        "/bin/mv -f /etc/sysconfig/windowmanager.old /etc/sysconfig/windowmanager"
      )
      ret
    end

    # check if given package is installed in the system selected for update
    # (currently mounted under /mnt)
    def PackageInstalled(package)
      SCR.Execute(
        path(".target.bash"),
        Builtins.sformat("rpm -q %1 --root /mnt", package)
      ) == 0
    end

    def SetDesktopPattern
      desktop = ReadInstalledDesktop()
      if Builtins.contains(
          ["kde", "kde4", "xfce", "lxde", "gnome", "startkde", "startkde4"],
          desktop
        )
        # 'gnome'/'startkde' could be default values even if not installed,
        # check the real state (bnc#737402)
        if desktop == "gnome"
          if !PackageInstalled("gnome-session")
            Builtins.y2milestone(
              "GNOME not present: not installing new desktop"
            )
            return
          end
        elsif desktop == "startkde" || desktop == "startkde4"
          if PackageInstalled("kdebase3-session") ||
              PackageInstalled("kdebase4-session")
            desktop = "kde4"
          else
            Builtins.y2milestone("KDE not present: not installing new desktop")
            return
          end
        end

        Builtins.y2milestone("Selecting pattern to install: %1", desktop)
        Pkg.ResolvableInstall(desktop, :pattern)
      end

      nil
    end

    #
    def Detach
      Pkg.TargetFinish
      @did_init1 = false
      @did_init2 = false

      nil
    end

    def TextsUsedInFuture
      # TRANSLATORS: check-box, it might happen that we need to downgrade some packages during update
      aaa = _("Allow Package Downgrade")

      nil
    end

    publish :variable => :packages_to_install, :type => "integer"
    publish :variable => :packages_to_update, :type => "integer"
    publish :variable => :packages_to_remove, :type => "integer"
    publish :variable => :unknown_packages, :type => "integer"
    publish :variable => :solve_errors, :type => "integer"
    publish :variable => :silentlyDowngradePackages, :type => "boolean"
    publish :variable => :keepInstalledPatches, :type => "boolean"
    publish :variable => :disallow_upgrade, :type => "boolean"
    publish :variable => :did_init1, :type => "boolean"
    publish :variable => :did_init2, :type => "boolean"
    publish :variable => :last_runlevel, :type => "integer"
    publish :variable => :onlyUpdateInstalled, :type => "boolean"
    publish :variable => :selected_selection, :type => "string"
    publish :variable => :products_incompatible, :type => "boolean"
    publish :variable => :updateBasePackages, :type => "boolean"
    publish :variable => :packagesInstalled, :type => "integer"
    publish :variable => :manual_interaction, :type => "boolean"
    publish :function => :OnlyUpdateInstalled, :type => "boolean ()"
    publish :function => :SilentlyDowngradePackages, :type => "boolean ()"
    publish :function => :IsProductSupportedForUpgrade, :type => "boolean ()"
    publish :function => :SelectedProducts, :type => "list <string> ()"
    publish :function => :ProductsCompatible, :type => "boolean ()"
    publish :function => :IgnoreProductCompatibility, :type => "void ()"
    publish :function => :InitUpdate, :type => "void ()"
    publish :function => :DropObsoletePackages, :type => "void ()"
    publish :function => :Reset, :type => "void ()"
    publish :function => :fill_version_map, :type => "void (map <string, any> &)"
    publish :function => :GetProductName, :type => "boolean ()"
    publish :function => :GetBasePatterns, :type => "list <string> ()"
    publish :function => :SetDesktopPattern, :type => "void ()"
    publish :function => :Detach, :type => "void ()"
  end

  Update = UpdateClass.new
  Update.main
end
