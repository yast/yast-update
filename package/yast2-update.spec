#
# spec file for package yast2-update
#
# Copyright (c) 2013 SUSE LINUX Products GmbH, Nuernberg, Germany.
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

# Please submit bugfixes or comments via http://bugs.opensuse.org/
#


Name:           yast2-update
Version:        3.1.17
Release:        0

BuildRoot:      %{_tmppath}/%{name}-%{version}-build
Source0:        %{name}-%{version}.tar.bz2

Group:          System/YaST
License:        GPL-2.0
BuildRequires:	update-desktop-files
BuildRequires:  yast2-devtools >= 3.1.15
BuildRequires:  yast2-ruby-bindings >= 1.0.0
BuildRequires:  yast2 >= 3.1.28
BuildRequires:  yast2-packager

# xmllint
BuildRequires:	libxml2-tools

# control.rng
BuildRequires:	yast2-installation-control

# Needed for tests
BuildRequires:  rubygem-rspec

# Stroage::ChangeDmNamesFromCrypttab
Requires:	yast2-storage >= 2.22.9
# OSRelease
Requires:	yast2 >= 3.1.28
Requires:	yast2-installation

# product update summary
Requires:	yast2-packager >= 3.1.24

# Pkg.TargetInitializeOptions()
Requires:       yast2-pkg-bindings >= 3.1.14

# moved into yast2-update from yast2-installation
# to remove dependency on yast2-storage
Provides:	yast2-installation:/usr/share/YaST2/clients/vendor.ycp

# Pkg::PkgUpdateAll (map conf)
Conflicts:	yast2-pkg-bindings < 2.15.11
# Storage::DeviceMatchFstab (#244117)
Conflicts:	yast2-storage < 2.15.4

Requires:       yast2-ruby-bindings >= 1.0.0

Summary:	YaST2 - Update

%package FACTORY
Group:		System/YaST
PreReq:		%fillup_prereq
Requires:	yast2-update yast2

# moved into yast2-update from yast2-installation
# to remove dependency on yast2-storage
Provides:	yast2-update:/usr/share/YaST2/clients/update.ycp

Requires:       yast2-ruby-bindings >= 1.0.0

Summary:	YaST2 - Update

%description
Use this component if you wish to update your system.

%description FACTORY
Use this component if you wish to update your system.

%prep
%setup -n %{name}-%{version}

%build
%yast_build

%install
%yast_install


%files
%defattr(-,root,root)
%{yast_ybindir}/*
%dir %{yast_moduledir}
%{yast_moduledir}/*

%{yast_clientdir}/inst_rootpart.rb
%{yast_clientdir}/inst_update.rb
%{yast_clientdir}/inst_backup.rb
%{yast_clientdir}/rootpart_proposal.rb
%{yast_clientdir}/update_proposal.rb
%{yast_clientdir}/packages_proposal.rb
%{yast_clientdir}/backup_proposal.rb
%{yast_clientdir}/inst_update_partition.rb
%{yast_clientdir}/inst_update_partition_auto.rb
%{yast_clientdir}/rootpart_check_keyboard.rb

%dir %{yast_yncludedir}
%{yast_yncludedir}/update
%{yast_yncludedir}/update/rootpart.rb

%doc %{yast_docdir}

%files FACTORY
%defattr(-,root,root)
%dir %{yast_desktopdir}
%{yast_desktopdir}/update.desktop
%dir %{yast_controldir}
%{yast_controldir}/update.xml
%{yast_clientdir}/update.rb
%{yast_clientdir}/run_update.rb
