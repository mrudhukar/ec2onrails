#!/bin/sh

#    This file is part of EC2 on Rails.
#    http://rubyforge.org/projects/ec2onrails/
#
#    Copyright 2007 Paul Dowman, http://pauldowman.com/
#
#    EC2 on Rails is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    EC2 on Rails is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.


# Generate a new self-signed cert and key for https

echo "Generating default self-signed SSL cert and key..."

cd /tmp
openssl genrsa -out /etc/ssl/private/default.key 1024
openssl req -new -key /etc/ssl/private/default.key -out server.csr <<END
CA
.
.
.
.
.
.
.
.

END
openssl x509 -req -days 365 -in server.csr -signkey /etc/ssl/private/default.key -out /etc/ssl/certs/default.crt