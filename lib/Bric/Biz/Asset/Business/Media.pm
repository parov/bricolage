package Bric::Biz::Asset::Business::Media;
###############################################################################

=head1 NAME

Bric::Biz::Asset::Business::Media - The parent class of all media objects

=head1 VERSION

$LastChangedRevision$

=cut

require Bric; our $VERSION = Bric->VERSION;

=head1 DATE

$LastChangedDate$

=head1 SYNOPSIS

  use Bric::Biz::Asset::Business::Media;

=head1 DESCRIPTION

Media contains all of the data that will result in published media files. It
contains the metadata and associations with media documents. It inherits from
L<Bric::Biz::Asset::Business|Bric::Biz::Asset::Business>

=cut

#==============================================================================#
# Dependencies                         #
#======================================#

#--------------------------------------#
# Standard Dependencies
use strict;

#--------------------------------------#
# Programatic Dependencies
use Bric::Biz::Asset::Business::Parts::Instance::Media;
use Bric::Biz::Workflow qw(MEDIA_WORKFLOW);
use Bric::Util::Coll::Instance::Media;
use Bric::Util::DBI qw(:all);
use Bric::Util::Trans::FS;
use Bric::Util::Grp::Media;
use Bric::Util::Time qw(:all);
use Bric::App::MediaFunc;
use Bric::App::Session qw(get_user_id);
use File::Temp qw( tempfile );
use Bric::Config qw(:media :thumb MASON_COMP_ROOT PREVIEW_ROOT);
use Bric::Util::Fault qw(:all);
use Bric::Util::MediaType;

#==============================================================================#
# Inheritance                          #
#======================================#

# The parent module should have a 'use' line if you need to import from it.
# use Bric;
use base qw( Bric::Biz::Asset::Business );

#=============================================================================#
# Function Prototypes                  #
#======================================#


# None

#==============================================================================#
# Constants                            #
#======================================#

use constant MIME_FILE_ROOT => Bric::Util::Trans::FS->cat_dir(
    MASON_COMP_ROOT->[0][1], qw(media mime)
);

use constant MIME_URI_ROOT => Bric::Util::Trans::FS->cat_uri('', qw(media mime));

use constant DEBUG => 0;

use constant TABLE  => 'media';

use constant INSTANCE_TABLE => 'media_instance';

use constant VERSION_TABLE => 'media_version';

use constant ID_COL => 'mt.id';

use constant COLS           => qw( uuid
                                   element__id
                                   priority
                                   source__id
                                   current_version
                                   published_version
                                   usr__id
                                   first_publish_date
                                   publish_date
                                   expire_date
                                   cover_date
                                   workflow__id
                                   desk__id
                                   publish_status
                                   active
                                   site__id
                                   alias_id);

use constant INSTANCE_COLS   => qw( name
                                   description
                                   input_channel__id
                                   file_size
                                   file_name
                                   location
                                   uri );
                                   
use constant VERSION_COLS   => qw( media__id
                                   version
                                   checked_out
                                   usr__id
                                   media_type__id
                                   category__id
                                   primary_oc__id
                                   primary_ic__id
                                   note );

use constant FIELDS         => qw( uuid
                                   element__id
                                   priority
                                   source__id
                                   current_version
                                   published_version
                                   user__id
                                   first_publish_date
                                   publish_date
                                   expire_date
                                   cover_date
                                   workflow_id
                                   desk_id
                                   publish_status
                                   _active
                                   site_id
                                   alias_id);

use constant INSTANCE_FIELDS => qw( name
                                   description
                                   input_channel_id
                                   size
                                   file_name
                                   location
                                   uri );
                                   
use constant VERSION_FIELDS => qw( id
                                   version
                                   checked_out
                                   modifier
                                   media_type_id
                                   category__id
                                   primary_oc_id
                                   primary_ic_id
                                   note );

use constant RO_FIELDS      => qw( class_id );
use constant RO_COLUMNS     => ', at.biz_class__id';

use constant GROUP_PACKAGE => 'Bric::Util::Grp::Media';
use constant INSTANCE_GROUP_ID => 32;

# let Asset know not to throw an exception
use constant CAN_DO_LIST_IDS => 1;
use constant CAN_DO_LIST => 1;
use constant CAN_DO_LOOKUP => 1;
use constant HAS_CLASS_ID => 1;

use constant GROUP_COLS => ('id_list(DISTINCT m.grp__id) AS grp_id',
                            'id_list(DISTINCT c.asset_grp_id) AS cat_grp_id',
                            'id_list(DISTINCT w.asset_grp_id) AS wf_grp_id');

# the mapping for building up the where clause based on params
use constant WHERE => 'mt.id = v.media__id '
  . 'AND v.id = mimv.media_version__id '
  . 'AND i.id = mimv.media_instance__id '
  . 'AND mm.object_id = mt.id '
  . 'AND m.id = mm.member__id '
  . "AND m.active = '1' "
  . 'AND c.id = v.category__id '
  . 'AND e.id = mt.element__id '
  . 'AND at.id = e.type__id '
  . 'AND mt.workflow__id = w.id';

use constant COLUMNS => join(', mt.', 'mt.id', COLS) . ', '
                      . join(', i.', 'i.id', INSTANCE_COLS) . ', '
                      . join(', v.', 'v.id', VERSION_COLS);

use constant OBJECT_SELECT_COLUMN_NUMBER => scalar COLS + 1;

# param mappings for the big select statement
use constant FROM => INSTANCE_TABLE . ' i, ' . VERSION_TABLE . ' v, media_instance__media_version mimv';

use constant PARAM_FROM_MAP => {
     keyword              => 'media_keyword mk, keyword k',
     output_channel_id    => 'media__output_channel moc',
     input_channel_id     => 'media__input_channel mic',
     simple               => 'media_member mm, member m, at_type at, element e, '
                             . 'category c, workflow w,' . TABLE . ' mt ',
     grp_id               => 'member m2, media_member mm2',
     data_text            => 'media_data_tile md',
     subelement_key_name  => 'media_container_tile mct',
     related_story_id     => 'media_container_tile mctrs',
     related_media_id     => 'media_container_tile mctrm',
     contrib_id           => 'media__contributor sic',
     note                 => 'media_version mv2',
};

PARAM_FROM_MAP->{_not_simple} = PARAM_FROM_MAP->{simple};

use constant PARAM_WHERE_MAP => {
      id                    => 'mt.id = ?',
      exclude_id            => 'mt.id <> ?',
      active                => 'mt.active = ?',
      inactive              => 'mt.active = ?',
      alias_id              => 'mt.alias_id = ?',
      site_id               => 'mt.site__id = ?',
      no_site_id            => 'mt.site__id <> ?',
      workflow__id          => 'mt.workflow__id = ?',
      workflow_id           => 'mt.workflow__id = ?',
      _null_workflow_id     => 'mt.workflow__id IS NULL',
      element__id           => 'mt.element__id = ?',
      element_id            => 'mt.element__id = ?',
      instance_id           => 'i.id = ?',
      version_id            => 'v.id = ?',
      element_key_name      => 'mt.element__id = e.id AND LOWER(e.key_name) LIKE LOWER(?)',
      source__id            => 'mt.source__id = ?',
      source_id             => 'mt.source__id = ?',
      priority              => 'mt.priority = ?',
      publish_status        => 'mt.publish_status = ?',
      first_publish_date_start => 'mt.publish_date >= ?',
      first_publish_date_end   => 'mt.publish_date <= ?',
      publish_date_start    => 'mt.publish_date >= ?',
      publish_date_end      => 'mt.publish_date <= ?',
      cover_date_start      => 'mt.cover_date >= ?',
      cover_date_end        => 'mt.cover_date <= ?',
      expire_date_start     => 'mt.expire_date >= ?',
      expire_date_end       => 'mt.expire_date <= ?',
      unexpired             => '(mt.expire_date IS NULL OR mt.expire_date > CURRENT_TIMESTAMP)',
      desk_id               => 'mt.desk__id = ?',
      name                  => 'LOWER(i.name) LIKE LOWER(?)',
      subelement_key_name   => 'i.id = mct.object_instance_id AND LOWER(mct.key_name) LIKE LOWER(?)',
      related_story_id       => 'i.id = mctrs.object_instance_id AND mctrs.related_instance__id = ?',
      related_media_id       => 'i.id = mctrm.object_instance_id AND mctrm.related_media__id = ?',
      data_text             => 'LOWER(md.short_val) LIKE LOWER(?) AND md.object_instance_id = i.id',
      title                 => 'LOWER(i.name) LIKE LOWER(?)',
      description           => 'LOWER(i.description) LIKE LOWER(?)',
      version               => 'v.version = ?',
      published_version     => "mt.published_version = v.version AND v.checked_out = '0'",
      user__id              => 'v.usr__id = ?',
      user_id               => 'v.usr__id = ?',
      uri                   => 'LOWER(i.uri) LIKE LOWER(?)',
      file_name             => 'LOWER(i.file_name) LIKE LOWER(?)',
      location              => 'LOWER(i.location) LIKE LOWER(?)',
      _checked_in_or_out    => 'v.checked_out = '
                             . '( SELECT checked_out '
                             . 'FROM media_version '
                             . 'WHERE version = v.version '
                             . 'AND media__id = v.media__id '
                             . 'ORDER BY checked_out DESC LIMIT 1 )',
      checked_in            => 'v.checked_out = '
                             . '( SELECT checked_out '
                             . 'FROM media_version '
                             . 'WHERE version = v.version '
                             . 'AND media__id = v.media__id '
                             . 'ORDER BY checked_out ASC LIMIT 1 )',
      _checked_out          => 'v.checked_out = ?',
      checked_out           => 'v.checked_out = ?',
      _not_checked_out       => "v.checked_out = '0' AND mt.id not in "
                              . '(SELECT media__id FROM media_version '
                              . 'WHERE mt.id = media_version.media__id '
                              . "AND media_version.checked_out = '1')",
      primary_oc_id         => 'v.primary_oc__id = ?',
      output_channel_id     => '(v.id = moc.media_version__id AND '
                             . 'moc.output_channel__id = ?)',
      primary_ic_id         => 'v.primary_ic__id = ?',
      input_channel_id      => 'i.input_channel__id = ?',
      primary_ic            => 'v.primary_ic__id = i.input_channel__id',
      category__id          => 'v.category__id = ?',
      category_id           => 'v.category__id = ?',
      category_uri          => 'v.category__id = c.id AND '
                             . 'LOWER(c.uri) LIKE LOWER(?)',
      keyword               => 'mk.media_id = mt.id AND '
                             . 'k.id = mk.keyword_id AND '
                             . 'LOWER(k.name) LIKE LOWER(?)',
      _no_return_versions   => 'mt.current_version = v.version',
      grp_id                => 'm2.grp__id = ? AND '
                             . "m2.active = '1' AND "
                             . 'mm2.member__id = m2.id AND '
                             . 'mt.id = mm2.object_id',
      simple                => 'mt.id IN ('
                             . 'SELECT mmt.id FROM media mmt '
                             . 'JOIN media_instance mi2 ON media__id = mmt.id '
                             . 'WHERE LOWER(mi2.name) LIKE LOWER(?) '
                             . 'OR LOWER(mi2.description) LIKE LOWER(?) '
                             . 'OR LOWER(mi2.uri) LIKE LOWER(?) '
                             . 'UNION SELECT media_id FROM media_keyword '
                             . 'JOIN keyword kk ON (kk.id = keyword_id) '
                             . 'WHERE LOWER(kk.name) LIKE LOWER(?))',
      contrib_id            => 'v.id = sic.media_version__id AND sic.member__id = ?',
      note                  => 'mv2.media__id = mt.id AND LOWER(mv2.note) LIKE LOWER(?)',
};

use constant PARAM_ANYWHERE_MAP => {
    element_key_name       => [ 'mt.element__id = e.id',
                                'LOWER(e.key_name) LIKE LOWER(?)' ],
    subelement_key_name    => [ 'i.id = mct.object_instance_id',
                                'LOWER(mct.key_name) LIKE LOWER(?)' ],
    related_story_id       => [ 'i.id = mctrs.object_instance_id',
                                'mctrs.related_instance__id = ?' ],
    related_media_id       => [ 'i.id = mctrm.object_instance_id',
                                'mctrm.related_media__id = ?' ],
    data_text              => [ 'md.object_instance_id = i.id',
                                'LOWER(md.short_val) LIKE LOWER(?)' ],
    output_channel_id      => ['v.id = moc.media_version__id',
                               'moc.output_channel__id = ?'],
    input_channel_id       => [ 'i.input_channel__id = ?' ],
    category_uri           => [ 'v.category__id = c.id',
                                'LOWER(c.uri) LIKE LOWER(?)' ],
    keyword                => [ 'mk.media_id = mt.id AND k.id = mk.keyword_id',
                                'LOWER(k.name) LIKE LOWER(?)' ],
    grp_id                 => [ "m2.active = '1' AND mm2.member__id = m2.id AND mt.id = mm2.object_id",
                                'm2.grp__id = ?' ],
    contrib_id             => [ 'i.id = mic.media_version__id',
                                'mic.member__id = ?' ],
    note                   => [ 'mv2.media__id = mt.id',
                                'LOWER(mv2.note) LIKE LOWER(?)'],
};

use constant PARAM_ORDER_MAP => {
    active              => 'mt.active',
    inactive            => 'mt.active',
    alias_id            => 'mt.alias_id',
    site_id             => 'mt.site__id',
    workflow__id        => 'mt.workflow__id',
    workflow_id         => 'mt.workflow__id',
    uri                 => 'LOWER(i.uri)',
    element__id         => 'mt.element__id',
    element_id          => 'mt.element__id',
    source__id          => 'mt.source__id',
    source_id           => 'mt.source__id',
    priority            => 'mt.priority',
    publish_status      => 'mt.publish_status',
    first_publish_date  => 'mt.first_publish_date',
    publish_date        => 'mt.publish_date',
    cover_date          => 'mt.cover_date',
    expire_date         => 'mt.expire_date',
    name                => 'LOWER(i.name)',
    title               => 'LOWER(i.name)',
    file_name           => 'LOWER(i.file_name)',
    location            => 'LOWER(i.location)',
    category_id         => 'v.category__id',
    category__id        => 'v.category__id',
    description         => 'LOWER(i.description)',
    version             => 'v.version',
    version_id          => 'v.id',
    instance_id         => 'i.id',
    user__id            => 'v.usr__id',
    _checked_out        => 'v.checked_out',
    primary_oc_id       => 'v.primary_oc__id',
    primary_ic_id       => 'v.primary_ic__id',
    category_uri        => 'LOWER(i.uri)',
    keyword             => 'LOWER(k.name)',
    return_versions     => 'v.version',
};

use constant DEFAULT_ORDER => 'cover_date';

#==============================================================================#
# Fields                               #
#======================================#

#--------------------------------------#
# Public Class Fields

# Public fields should use 'vars'
#use vars qw();

#--------------------------------------#
# Private Class Fields
my ($meths, @ord);

#--------------------------------------#
# Instance Fields

BEGIN {
    Bric::register_fields(
                        {
                         # Public Fields
                         location        => Bric::FIELD_READ,
                         file_name       => Bric::FIELD_READ,
                         uri             => Bric::FIELD_READ,
                         media_type_id   => Bric::FIELD_RDWR,
                         category__id    => Bric::FIELD_RDWR,
                         size            => Bric::FIELD_RDWR,
                         class_id        => Bric::FIELD_READ,
                         needs_preview   => Bric::FIELD_READ,

                         # Private Fields
                         _category_obj   => Bric::FIELD_NONE,
                         _file           => Bric::FIELD_NONE,
                         _media_type_obj => Bric::FIELD_NONE,
                        });
}

#==============================================================================#
# Interface Methods                    #
#======================================#

=head1 INTERFACE

=head2 Constructors

=over 4

=cut

#--------------------------------------#
# Constructors

#------------------------------------------------------------------------------#

=item $media = Bric::Biz::Asset::Business::Media->new( $initial_state )

This will create a new media object with an optionally defined initial state

Supported Keys:

=over 4

=item *

user__id - Required.

=item *

active

=item *

priority

=item *

title - same as name

=item *

name - Will be overridden by title

=item *

description

=item *

workflow_id

=item *

element__id - Required unless asset type object passed

=item *

element - the object required unless id is passed

=item *

site_id - required

=item *

source__id - required

=item *

cover_date - will set expire date in conjunction with the source

=item *

media_type_id

=item *

category__id

=back

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub new {
    my ($self, $init) = @_;
    # default to active unless passed otherwise
    $init->{_active} = (exists $init->{active}) ? $init->{active} : 1;
    delete $init->{active};
    $init->{priority} ||= 3;
    $init->{media_type_id} ||= 0;
    $init->{name} = delete $init->{title} if exists $init->{title};
    $self->SUPER::new($init);
}

################################################################################

=item $media = Bric::Biz::Asset::Business::Media->lookup( { id => $id })

This will return a media asset that matches the criteria defined

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> Inherited from Bric::Biz::Asset.

=cut

################################################################################

=item (@media || $media) =  Bric::Biz::Asset::Business::Media->list($param);

returns a list or list ref of media objects that match the criteria defined

Supported Keys:

=over 4

=item title

The title of the media document. May use C<ANY> for a list of possible values.

=item name

Same as C<title>.

=item description

Media Document description. May use C<ANY> for a list of possible values.

=item id

The media document ID. May use C<ANY> for a list of possible values.

=item exclude_id

A media document ID to exclude from the list. May use C<ANY> for a list of
possible values.

=item version

The media document version number. May use C<ANY> for a list of possible values.

=item instance_id

The ID of a version of a media document. May use C<ANY> for a list of possible
values.

=item file_name

The media document file name. May use C<ANY> for a list of possible values.

=item user_id

Returns the versions that are checked out by the user, otherwise returns the
most recent version. May use C<ANY> for a list of possible values.

=item checked_out

A boolean value indicating whether to return only checked out or not checked
out media.

=item checked_in

If passed a true value, this parameter causes the checked in version of the
most current version of the media document to be returned. When a media
document is checked out, there are two instances of the current version: the
one checked in last, and the one currently being edited. When the
C<checked_in> parameter is a true value, then the instance last checked in is
returned, rather than the instance currently checked out. This is useful for
users who do not currently have a media document checked out and wish to see
the media document as of the last check in, rather than as currently being
worked on in the current checkout. If a media document is not currently
checked out, this parameter has no effect.

=item published_version

Returns the versions of the media documents as they were last published. The
C<checked_out> parameter will be ignored if this parameter is passed a true
value.

=item return_versions

Boolean indicating whether to return pass version objects for each media document
listed.

=item active

Boolean indicating whether to return active or inactive media.

=item inactive

Returns only inactive media.

=item alias_id

Returns a list of media aliased to the media ID passed as its value. May use
C<ANY> for a list of possible values.

=item category_id

Returns a list of media in the category represented by a category ID. May
use C<ANY> for a list of possible values.

=item category_uri

Returns a list of media with a given category URI. May use C<ANY> for a list
of possible values.

=item keyword

Returns media associated with a given keyword string (not object). May use
C<ANY> for a list of possible values.

=item note

Returns media with a note matching the value associated with any of their
versions. May use C<ANY> for a list of possible values.

=item workflow_id

Return a list of media in the workflow represented by the workflow ID. May
use C<ANY> for a list of possible values.

=item desk_id

Returns a list of media on a desk with the given ID. May use C<ANY> for a list
of possible values.

=item uri

Returns a list of media with a given URI. May use C<ANY> for a list of
possible values.

=item site_id

Returns a list of media associated with a given site ID. May use C<ANY>
for a list of possible values.

=item element_id

Returns a list of media associated with a given element ID. May use C<ANY>
for a list of possible values.

=item source_id

Returns a list of media associated with a given source ID. May use C<ANY>
for a list of possible values.

=item output_channel_id

Returns a list of media associated with a given output channel ID. May use
C<ANY> for a list of possible values.

=item primary_oc_id

Returns a list of media associated with a given primary output channel
ID. May use C<ANY> for a list of possible values.

=item input_channel_id

Returns a list of media associated with a given input channel ID. May use
C<ANY> for a list of possible values.

=item primary_ic_id

Returns a list of media associated with a given primary input channel
ID. May use C<ANY> for a list of possible values.

=item priority

Returns a list of media associated with a given priority value. May use
C<ANY> for a list of possible values.

=item contrib_id

Returns a list of media associated with a given contributor ID. May use
C<ANY> for a list of possible values.

=item grp_id

Returns a list of media that are members of the group with the specified group
ID. May use C<ANY> for a list of possible values.

=item publish_status

Boolean value indicating whether to return published or unpublished media.

=item first_publish_date_start

Returns a list of media first published on or after a given date/time.

=item first_publish_date_end

Returns a list of media first published on or before a given date/time.

=item publish_date_start

Returns a list of media last published on or after a given date/time.

=item publish_date_end

Returns a list of media last published on or before a given date/time.

=item cover_date_start

Returns a list of media with a cover date on or after a given date/time.

=item cover_date_end

Returns a list of media with a cover date on or before a given date/time.

=item expire_date_start

Returns a list of media with a expire date on or after a given date/time.

=item expire_date_end

Returns a list of media with a expire date on or before a given date/time.

=item unexpired

A boolean parameter. Returns a list of media without an expire date, or with
an expire date set in the future.

=item element_key_name

The key name for the media type element. May use C<ANY> for a list of possible
values.

=item subelement_key_name

The key name for a container element that's a subelement of a media
document. May use C<ANY> for a list of possible values.

=item related_story_id

Returns a list of media that have this story ID as a related story. May use
C<ANY> for a list of possible values.

=item related_media_id

Returns a list of media that have this media ID as a related media document.
May use C<ANY> for a list of possible values.

=item data_text

Text stored in the fields of the media element or any of its subelements. Only
fields that use the "short" storage type will be searched. May use C<ANY> for
a list of possible values.

=item simple

Triggers a single OR search that hits title, description, uri and keywords.

=item Order

A property name to order by.

=item OrderDirection

The direction in which to order the records, either "ASC" for ascending (the
default) or "DESC" for descending.

=item Limit

A maximum number of objects to return. If not specified, all objects that
match the query will be returned.

=item Offset

The number of objects to skip before listing the remaining objcts or the
number of objects specified by C<Limit>.

=back

B<Throws:>

=over 4

=item *

Unable to connect to database.

=item *

Unable to prepare SQL statement.

=item *

Unable to select column into arrayref.

=item *

Unable to execute SQL statement.

=item *

Unable to bind to columns to statement handle.

=item *

Unable to fetch row from statement handle.

=back

B<Side Effects:>

NONE

B<Notes:> Inherited from Bric::Biz::Asset.

=cut

################################################################################

#--------------------------------------#

=back

=head2 Destructors

=over 4

=item $self->DESTROY

dummy method to not waste the time of AUTOLOAD

=cut

sub DESTROY {
    # This method should be here even if its empty so that we don't waste time
    # making Bricolage's autoload method try to find it.
}

################################################################################

#--------------------------------------#

=back

=head2 Public Class Methods

=over 4

=item (@ids||$id_list) = Bric::Biz::Asset::Business::Media->list_ids( $criteria );

Returns a list or list ref of media object IDs that match the criteria defined.
The criteria are the same as those for the list() method.

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> Inherited from Bric::Biz::Asset.

=cut

################################################################################

=item ($fields || @fields) =
        Bric::Biz::Asset::Business::Media::autopopulated_fields()

Returns a list of the names of fields that are registered in the database as
being autopopulatable for a given sub class

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub autopopulated_fields {
    my $self = shift;
    my $fields = $self->_get_auto_fields;
    return wantarray ? keys %$fields : [keys %$fields];
}

################################################################################

=item my $key_name = Bric::Biz::Asset::Business::Media->key_name()

Returns the key name of this class.

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub key_name { 'media' }

################################################################################

=item my $hashref = Bric::Biz::Asset::Business::Media->thumbnail_uri()

This method returns a local URI pointing to an icon representing the media type
of the media document. If no file has been uploaded to the media document,
C<thumbnail_uri()> will return C<undef>.

This method is only enabled if the C<USE_THUMBNAILS> F<bricolage.conf>
directive is enabled. It may be overridden in subclasses to return a different
URI value (See Bric::Biz::Asset::Business::Media::Image for an example).

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub thumbnail_uri {
    return unless USE_THUMBNAILS;
    my $self = shift;
    return unless $self->get_path;

    # Just return the default icon if there is no media type (unlikely).
    my $mime = $self->get_media_type or return
      Bric::Util::Trans::FS->cat_uri(MIME_URI_ROOT, 'none.png');
    $mime = $mime->get_name;
    my ($cat, $type) = split '/', $mime, 2;

    # If there's a PNG file for this media type, return its URI.
    return Bric::Util::Trans::FS->cat_uri(MIME_URI_ROOT, "$mime.png")
      if -e Bric::Util::Trans::FS->cat_file(MIME_FILE_ROOT, $cat, "$type.png");

    # If there's a PNG file for the media type category, return its URI.
    return Bric::Util::Trans::FS->cat_uri(MIME_URI_ROOT, "$cat.png")
      if -e Bric::Util::Trans::FS->cat_file(MIME_FILE_ROOT, "$cat.png");

    # Otherwise, just return the default icon.
    return Bric::Util::Trans::FS->cat_uri(MIME_URI_ROOT, 'none.png');
}

################################################################################

=item $meths = Bric::Biz::Asset::Business::Media->my_meths

=item (@meths || $meths_aref) = Bric::Biz::Asset::Business::Media->my_meths(TRUE)

=item my (@meths || $meths_aref) = Bric::Biz:::Asset::Business::Media->my_meths(0, TRUE)

Returns an anonymous hash of introspection data for this object. If called
with a true argument, it will return an ordered list or anonymous array of
introspection data. If a second true argument is passed instead of a first,
then a list or anonymous array of introspection data will be returned for
properties that uniquely identify an object (excluding C<id>, which is
assumed).

Each hash key is the name of a property or attribute of the object. The value
for a hash key is another anonymous hash containing the following keys:

=over 4

=item name

The name of the property or attribute. Is the same as the hash key when an
anonymous hash is returned.

=item disp

The display name of the property or attribute.

=item get_meth

A reference to the method that will retrieve the value of the property or
attribute.

=item get_args

An anonymous array of arguments to pass to a call to get_meth in order to
retrieve the value of the property or attribute.

=item set_meth

A reference to the method that will set the value of the property or
attribute.

=item set_args

An anonymous array of arguments to pass to a call to set_meth in order to set
the value of the property or attribute.

=item type

The type of value the property or attribute contains. There are only three
types:

=over 4

=item short

=item date

=item blob

=back

=item len

If the value is a 'short' value, this hash key contains the length of the
field.

=item search

The property is searchable via the list() and list_ids() methods.

=item req

The property or attribute is required.

=item props

An anonymous hash of properties used to display the property or
attribute. Possible keys include:

=over 4

=item type

The display field type. Possible values are

=over 4

=item text

=item textarea

=item password

=item hidden

=item radio

=item checkbox

=item select

=back

=item length

The Length, in letters, to display a text or password field.

=item maxlength

The maximum length of the property or value - usually defined by the SQL DDL.

=back

=item rows

The number of rows to format in a textarea field.

=item cols

The number of columns to format in a textarea field.

=item vals

An anonymous hash of key/value pairs reprsenting the values and display names
to use in a select list.

=back

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub my_meths {
    my ($pkg, $ord, $ident) = @_;
    return if $ident;

    # Return 'em if we got em.
    return !$ord ? $meths : wantarray ? @{$meths}{@ord} : [@{$meths}{@ord}]
      if $meths;

    # We don't got 'em. So get 'em!
    foreach my $meth (__PACKAGE__->SUPER::my_meths(1)) {
        $meths->{$meth->{name}} = $meth;
        push @ord, $meth->{name};
    }

    push @ord, qw(file_name category category_name), pop @ord;
    $meths->{file_name} = {
                           get_meth => sub { shift->get_file_name(@_) },
                           get_args => [],
                           name     => 'file_name',
                           disp     => 'File Name',
                           len      => 256,
                           req      => 1,
                           type     => 'short',
                           props    => { type      => 'text',
                                         length    => 32,
                                         maxlength => 256
                                       }
                          };
    $meths->{category} = {
                          get_meth => sub { shift->get_category_object(@_) },
                          get_args => [],
                          name     => 'category',
                          disp     => 'Category',
                          len      => 64,
                          req      => 1,
                          type     => 'short',
                         };

    $meths->{category_name} = {
                          get_meth => sub { shift->get_category_object(@_)->get_name },
                          get_args => [],
                          name     => 'category_name',
                          disp     => 'Category Name',
                          len      => 64,
                          req      => 1,
                          type     => 'short',
                         };

    # Copy the data for the title from name.
    $meths->{title} = { %{ $meths->{name} } };
    $meths->{title}{name} = 'title';
    $meths->{title}{disp} = 'Title';

    # Rename element.
    $meths->{element} = { %{ $meths->{element} } };
    $meths->{element}{disp} = 'Media Type';
    return !$ord ? $meths : wantarray ? @{$meths}{@ord} : [@{$meths}{@ord}];
}

################################################################################

=item $class_id = Bric::Biz::Asset::Business::Media->get_class_id()

Returns the class id of the Media object or class.

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub get_class_id { ref $_[0] ? shift->_get('class_id') : 46 }

################################################################################

=item my $wf_type = Bric::Biz::Asset::Business::Media->workflow_type

Returns the value of the Bric::Biz::Workflow C<MEDIA_WORKFLOW> constant.

=cut

sub workflow_type { MEDIA_WORKFLOW }

################################################################################

#--------------------------------------#

=back

=head2 Public Instance Methods

=over 4

=item $media = $media->set_category__id($id)

Associates this media asset with the given category

B<Throws:> NONE.

B<Side Effects:> Updates the media document's URI and group associations.

B<Notes:> NONE.

=cut

sub set_category__id {
    my ($self, $cat_id) = @_;
    my $old_cat_id = $self->_get('category__id');
    return $self unless (defined $cat_id && not defined $old_cat_id)
      || (not defined $cat_id && defined $old_cat_id)
      || ($cat_id != $old_cat_id);

    my $cat = Bric::Biz::Category->lookup({ id => $cat_id });
    my $oc = $self->get_primary_oc;

    my $c_cat = $self->get_category_object();
    my @grp_ids;
    foreach ($self->get_grp_ids) {
        push @grp_ids, $_ unless $c_cat && $_ == $c_cat->get_asset_grp_id;
    }
    push @grp_ids, $cat->get_asset_grp_id();

    my ($uri, $update_uri);
    if ($self->get_file_name) {
        $update_uri = 1;
        $uri = Bric::Util::Trans::FS->cat_uri
          ( $self->_construct_uri($cat, $oc), $oc->get_filename($self));
    }

    $self->_set([qw(_category_obj category__id uri    grp_ids   _update_uri)] =>
                [   $cat,         $cat_id,     $uri, \@grp_ids, $update_uri]);

    return $self;
}

sub get_primary_uri { shift->get_uri }


##############################################################################
# Documented in Bric::Biz::Asset::Business.

sub set_primary_oc_id {
    my ($self, $id) = @_;
    my $oldid = $self->_get('primary_oc_id');
    if ((defined $id && ! defined $oldid) || $id != $oldid) {
        my ($uri, $update_uri);
        if ($self->get_file_name) {
            my $oc = Bric::Biz::OutputChannel->lookup({ id => $id });
            my $cat = $self->get_category_object;
            $update_uri = 1;
            $uri = Bric::Util::Trans::FS->cat_uri
              ( $self->_construct_uri($cat, $oc), $oc->get_filename($self));
        }
        $self->_set([qw(primary_oc_id uri   _update_uri)] =>
                    [   $id,          $uri, $update_uri]);
    }
    return $self;
}

################################################################################

=item $category_id = $media->get_category__id()

Returns the category id that has been associated with this media object

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

=item $self = $media->set_cover_date($cover_date)

Sets the cover date and updates the URI.

B<Throws:>

=over 4

=item *

Bric::_get() - Problems retrieving fields.

=item *

Unable to unpack date.

=item *

Unable to format date.

=item *

Incorrect number of args to Bric::_set().

=item *

Bric::set() - Problems setting fields.

=back

B<Side Effects:> Changes the media document's URI.

B<Notes:> NONE.

=cut

sub set_cover_date {
    my $self = shift;
    my $cover_date = db_date(shift);
    my ($old, $cat, $cat_id) =
      $self->_get(qw(cover_date _category_obj category__id));
    my $fn = $self->get_file_name;

    return $self unless (defined $cover_date && not defined $old)
      || (not defined $cover_date && defined $old)
      || ($cover_date ne $old);

    # Set the cover date so that _construct_uri() will be able to construct
    # the correct URI!
    $self->_set(['cover_date'] => [$cover_date]);

    my ($uri, $update_uri);
    if (defined $fn) {
        $update_uri = 1;
        $cat ||= Bric::Biz::Category->lookup({ id => $cat_id });
        my $oc = $self->get_primary_oc;
        if ($cat and $oc) {
            $uri = Bric::Util::Trans::FS->cat_uri
              ($self->_construct_uri($cat, $oc), $fn);
        }
    }

    $self->_set([qw(_update_uri  _category_obj uri)] =>
                [   $update_uri, $cat,         $uri]);
}

################################################################################

=item $category = $media->get_category_object()

=item $category = $media->get_category()

Returns the object of the category that this is a member of

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub get_category_object {
    my $self = shift;
    my $cat = $self->_get( '_category_obj' );
    return $cat if $cat;
    $cat = Bric::Biz::Category->lookup({ id => $self->_get('category__id') });
    $self->_set({ _category_obj => $cat });
    return $cat;
}

{ no warnings;
  *get_category = \&get_category_object;
}

##############################################################################

=item my $uri = $media->get_uri

=item my $uri = $media->get_uri($oc)

Returns the URI for the media object. If the C<$oc> output channel parameter
is passed in, then the URI will be returned in the output channel's preferred
format.

B<Throws:>

=over 4

=item *

Output channel not associated with media.

=back

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub get_uri {
    my ($self, $oc) = @_;

    # If it's an alias, we need to always construct the URI.
    $oc ||= $self->get_primary_oc if $self->_get_alias;

    # Just return the URI unless we need to format it according to an output
    # channel's requirements.
    return $self->_get('uri') unless $oc;

    # Make sure we have a valid output channel.
    $oc = Bric::Biz::OutputChannel->lookup({ id =>$oc })
      unless ref $oc;
    throw_da(error => "Output channel '" . $oc->get_name . "' not " .
                   "associated with media '" . $self->get_name . "'")
      unless $self->get_output_channels($oc->get_id);

    return Bric::Util::Trans::FS->cat_uri
      ($self->_construct_uri($self->get_category_object, $oc),
       $oc->get_filename($self));
}

##############################################################################

=item $uri = $media->get_local_uri()

Returns the uri of the media object for the Bricolage application server.

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub get_local_uri {
    my $self = shift;
    my $loc = $self->get_location || return;
    return Bric::Util::Trans::FS->cat_uri(MEDIA_URI_ROOT,
                                        Bric::Util::Trans::FS->dir_to_uri($loc) );
}

=item $uri = $media->get_path()

Returns the path of the media object on the Bricolage file system.

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub get_path {
    my $self = shift;
    my $loc = $self->get_location || return;
    return Bric::Util::Trans::FS->cat_dir(MEDIA_FILE_ROOT, $loc);
}

#------------------------------------------------------------------------------#

=item $mt_obj = $media->get_media_type()

Returns the media type object associated with this object.

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub get_media_type {
    my $self = shift;
    my ($mt_obj, $mt_id) = $self->_get('_media_type_obj', 'media_type_id');
    return unless defined $mt_id;

    unless ($mt_obj) {
        $mt_obj = Bric::Util::MediaType->lookup({'id' => $mt_id});
        $self->_set(['_media_type_obj'], [$mt_obj]);
    }
    return $mt_obj;
}

################################################################################

=item $media = $media->upload_file($file_handle, $file_name)

=item $media = $media->upload_file($file_handle, $file_name, $media_type)

=item $media = $media->upload_file($file_handle, $file_name, $media_type, $size)

Reads a file from the passed $file_handle and stores it in the media object
under $file_name. If $media_type is passed, it will be used to set the media
type of the file. Otherwise, C<upload_file()> will use Bric::Util::MediaType
to determine the media type. If $size is passed, its value will be used for
the size of the file; otherwise, C<upload_file()> will figure out the file
size itself.

B<Throws:> NONE.

B<Side Effects:> Closes the C<$file_handle> after reading. Updates the media
document's URI.

B<Notes:> NONE.

=cut

sub upload_file {
    my ($self, $fh, $name, $type, $size) = @_;

    my ($id, $v, $old_fn, $loc, $uri) =
      $self->_get(qw(id version file_name location uri));
    my $dir = Bric::Util::Trans::FS->cat_dir(MEDIA_FILE_ROOT, $id, $v);
    Bric::Util::Trans::FS->mk_path($dir);
    my $path = Bric::Util::Trans::FS->cat_dir($dir, $name);

    if (MEDIA_UNIQUE_FILENAME) {
        # split the uploaded filename into prefix and ext
        (my ($prefix,$ext)) = ($name =~  m/^(.+)(\.[^\.]+)$/ );
        # is this a new version of an existing ID ?
        if ($old_fn) {
            # set the prefix to the prefix of the old filename
            ($prefix) = ($old_fn =~ m/^(.+)\.[^\.]+$/i );
        } else {
            # generate a new prefix and make sure it is unique
            my $idexists = 1;
            while ($idexists) {
                # generate new random 8 character filename
                $prefix = substr(Digest::MD5::md5_hex(Digest::MD5::md5_hex(time.{}.$id.rand)), 0, 8);
                # add any required filename prefix if we need to 
                $prefix = MEDIA_FILENAME_PREFIX . $prefix if (MEDIA_FILENAME_PREFIX);
                # does this filename exist in DB regardless of extension ?
                ($idexists) = Bric::Biz::Asset::Business::Media->list_ids( {file_name => "$prefix%" } );
            }
        }
        # construct the new filename
        $name = $prefix . $ext;
    }

    open FILE, ">$path"
      or throw_gen(error => "Unable to open '$path': $!");
    my $buffer;
    while (read($fh, $buffer, 10240)) { print FILE $buffer }
    close $fh;
    close FILE;
    $self->_set(['needs_preview'] => [1]) if AUTO_PREVIEW_MEDIA;

    # Set the media type and the file size.
    if ($type = defined $type
        ? Bric::Util::MediaType->lookup({name => $type})
        : undef)
    {
        # We got a valid type.
        $self->_set(['media_type_id', '_media_type_obj'], [$type->get_id, $type]);
    } elsif (my $mid = Bric::Util::MediaType->get_id_by_ext($name)) {
        # We figured out the type by the filename extension.
        $self->_set(['media_type_id', '_media_type_obj'], [$mid, undef]);
    } else {
        # We have no idea what the type is. :-(
        $self->_set(['media_type_id', '_media_type_obj'], [0, undef]);
    }

    $self->set_size(defined $size ? $size : -s $path);

    # Get the Output Channel object.
    my $at_obj = $self->get_element_object;
    my $oc_obj = $self->get_primary_oc;

    my $new_loc = Bric::Util::Trans::FS->cat_dir('/', $id, $v, $name);

    # Set the location, name, and URI.
    if (not defined $old_fn
        or not defined $uri
        or $old_fn ne $name
        or $loc ne $new_loc) {
        $self->_set(['file_name'], [$name]);
        $uri = Bric::Util::Trans::FS->cat_uri
          ($self->_construct_uri($self->get_category_object, $oc_obj),
           $oc_obj->get_filename($self));

        $self->_set([qw(location  uri   _update_uri)] =>
                    [   $new_loc, $uri, 1]);
    }

    if (my $auto_fields = $self->_get_auto_fields) {
        # We need to autopopulate data field values. Get the top level element
        # construct a MediaFunc object.
        my $tile = $self->get_tile;
        my $path = Bric::Util::Trans::FS->cat_dir(MEDIA_FILE_ROOT, $new_loc);
        my $media_func = Bric::App::MediaFunc->new({ file_path => $path });

        # Iterate through all the elements.
        foreach my $dt ($tile->get_tiles) {
            # Skip container elements.
            next if $dt->is_container;
            # See if this is an auto populated field.
            my $name = $dt->get_name;
            if ($auto_fields->{$name} ) {
                # Check the tile to see if we can override it.
                next if $dt->is_locked;
                # Get and set the value
                my $method = $auto_fields->{$name};
                my $val = $media_func->$method();
                $dt->set_data(defined $val ? $val : '');
                $dt->save;
            }
        }
    }
    return $self;
}

sub delete_file {
    my ($self) = @_;
    
    $self->_set([qw(file_name location  uri _update_uri)] =>
                [   undef, undef, undef, 1]);
                
    return $self;
}

################################################################################

=item $file_name = $media->get_file_name()

Returns the name of the file for this given media object.

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub get_file_name { shift->get_instance->get_file_name(@_); }

################################################################################

=item $file_handle = $media->get_file()

Returns the file handle for this given media object

B<Throws:>

=over

=item *

Error getting File.

=back

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub get_file { shift->get_instance->get_file(@_); }

################################################################################

=item $location = $media->get_location()

The will return the location of the file on the file system, relative to
MEDIA_FILE_ROOT.

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub get_location { shift->get_instance->get_location(@_); }

################################################################################

=item $size = $media->get_size()

This is the size of the media file in bytes

B<Throws:>

=over 4

=item *

Unable to retrieve category__id of this media.

=back

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

##############################################################################

=item $media = $media->revert();

Reverts the current version to a prior version

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub revert {
    my ($self, $version) = @_;
    throw_gen(error => "May not revert a non checked out version")
      unless $self->_get('checked_out');

    my $revert_obj = __PACKAGE__->lookup({
        id          => $self->_get_id,
        version     => $version,
    }) or throw_gen "The requested version does not exist";


    # Delete existing contributors.
    if (my $contrib = $self->_get_contributors) {
        $self->delete_contributors([keys %$contrib]);
    }

    # Set up contributors to revert to.
    my $contrib;
    my $revert_contrib = $revert_obj->_get_contributors;
    while (my ($cid, $c) = each %$revert_contrib) {
        $c->{action} = 'insert';
        $contrib->{$cid} = $c;
    }

    # Clone the basic properties of the media document.
    my @attrs = qw(name description media_type_id category__id size file_name
                   location uri);
    $self->_set([@attrs, qw(_contributors _update_contributors _queried_contrib)],
                [$revert_obj->_get(@attrs), $contrib, 1, 1]);

    # clone the tiles
    # get rid of current tiles
    my $tile = $self->get_tile;
    $tile->do_delete;
    my $new_tile = $revert_obj->get_tile;
    $new_tile->prepare_clone;
    $self->_set({ _delete_tile => $tile,
                  _tile        => $new_tile});

    # Make sure the current version is cached.
    return $self->cache_me;
}

################################################################################

=item $media = $media->clone()

Clones the media object

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub clone {
    my $self = shift;
    my $tile = $self->get_tile();
    $tile->prepare_clone();

    my $contribs = $self->_get_contributors();
    # clone contributors
    foreach (keys %$contribs ) {
        $contribs->{$_}->{'action'} = 'insert';
    }

    $self->_set( { id                   => undef,
                   first_publish_date   => undef,
                   publish_date         => undef,
                   publish_status       => 0,
                   _update_contributors => 1
    });
    return $self;
}


################################################################################

=item $self = $self->save()

Saves the object to the database doing either an insert or
an update

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub save {
    my $self = shift;

    my ($id, $active, $update_uris, $preview) =
      $self->_get(qw(id _active _update_uri needs_preview));

    # Start a transaction.
    begin();
    eval {
        if ($id) {
            $self->_update_media();

            if ($self->_get('version_id')) {
                if ($self->_get('_cancel')) {
                    $self->_delete_version();
                    if ($self->_get('version') == 0) {
                        $self->_delete_media();
                    }
                    $self->_set( {'_cancel' => undef });
                    commit();
                    return $self;
                } else {
                    $self->_update_version();
                }
            } else {
                $self->_insert_version();
            }

        } else {
            # insert both
            if ($self->_get('_cancel')) {
                commit();
                return $self;
            } else {
                $self->_insert_media();
                $self->_insert_version();
            }
        }

        if ($active) {
            if ($update_uris) {
                if (my $fn = $self->get_file_name) {
                    # We have a file name, so we can create URIs. So update
                    # them.
                    $self->_update_uris;
                } else {
                    # No file name, no URIs.
                    $self->_set(['_update_uri'] => [0]);
                }
            }
        } else {
            $self->_delete_uris;
        }

        $self->SUPER::save();
        commit();
    };

    if (my $err = $@) {
        rollback();
        rethrow_exception($err);
    }
    if (AUTO_PREVIEW_MEDIA && $preview) {
        # Go ahead and distribute to the preview server(s).
        my $burner = Bric::Util::Burner->new({ out_dir => PREVIEW_ROOT });
        $burner->preview($self, 'media', get_user_id, $_->get_id)
          for $self->get_output_channels;
        $self->_set(['needs_preview'] => [0]);
    }

    return $self;
}

################################################################################

#--------------------------------------#

=item $contribs = $self->_get_contributors()

Returns the contributors from a cache or looks em up

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub _get_contributors {
    my $self = shift;

    my ($contrib, $queried) = $self->_get('_contributors', '_queried_contrib');

    unless ($contrib) {
        my $dirty = $self->_get__dirty();
        my $sql = 'SELECT member__id, place, role FROM media__contributor ' .
          'WHERE media_version__id=? ';

        my $sth = prepare_ca($sql, undef);
        execute($sth, $self->_get('version_id'));
        while (my $row = fetch($sth)) {
            $contrib->{$row->[0]}->{'role'} = $row->[2];
            $contrib->{$row->[0]}->{'place'} = $row->[1];
        }

        $self->_set( { _queried_contrib => 1,
                       _contributors     => $contrib
        });
        $self->_set__dirty($dirty);
    }
    return $contrib;
}

################################################################################

=item $self = $self->_insert_contributor( $id, $role)

Inserts a row into the mapping table for contributors.

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub _insert_contributor {
    my ($self, $id, $role, $place) = @_;

    my $sql = 'INSERT INTO media__contributor ' .
      ' (id, media_version__id, member__id, place, role) ' .
        " VALUES (${\next_key('media__contributor')},?,?,?,?) ";

    my $sth = prepare_c($sql, undef);
    execute($sth, $self->_get('version_id'), $id, $place, $role);
    return $self;
}

################################################################################

=item $self = $self->_update_contributor($id, $role)

Updates the contributor mapping table

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub _update_contributor {
    my ($self, $id, $role, $place) = @_;
    my $sql = 'UPDATE media__contributor ' .
      ' SET role=?, place=? ' .
        ' WHERE media_version__id=? ' .
          ' AND member__id=? ';

    my $sth = prepare_c($sql, undef);
    execute($sth, $role, $place, $self->_get('version_id'), $id);
    return $self;
}

################################################################################

=item $self = $self->_delete_contributors($id)

Deletes the rows from these mapping tables

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub _delete_contributor {
    my ($self, $id) = @_;

    my $sql = 'DELETE FROM media__contributor ' .
      ' WHERE media_version__id=? ' .
        ' AND member__id=? ';

    my $sth = prepare_c($sql, undef);
    execute($sth, $self->_get('version_id'), $id);
    return $self;
}

################################################################################

=item ($fields) = $self->_get_auto_fields($biz_pkg)

returns a hash ref of the fields that are to be autopopulated from this 
type of media object.

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub _get_auto_fields {
    my ($self) = @_;

    my $auto_fields;
    if (ref $self) {
        $auto_fields = $self->_get('_auto_fields');
        return $auto_fields if $auto_fields;
    }

    my $sth = prepare_c(qq{
        SELECT name, function_name
        FROM   media_fields
        WHERE  biz_pkg = ?
               AND active = ?
        ORDER BY id
    });

    execute($sth, ($self->get_class_id, 1));
    while (my $row = fetch($sth)) {
        $auto_fields->{$row->[0]} = $row->[1];
    }

    $self->_set( { '_auto_fields' => $auto_fields }) if ref $self;
    return $auto_fields;
}

################################################################################

=item $self = $self->_insert_media()

Inserts a media record into the database

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub _insert_media {
    my $self = shift;

    my $sql = 'INSERT INTO ' . TABLE . ' (id, ' . join(', ', COLS) . ') '.
      "VALUES (${\next_key(TABLE)}, ". join(', ',('?') x COLS).')';

    my $sth = prepare_c($sql, undef);
    execute($sth, $self->_get(FIELDS));
    $self->_set( { id => last_key(TABLE) });

    # And finally, register this person in the "All Media" group.
    $self->register_instance(INSTANCE_GROUP_ID, GROUP_PACKAGE);
    return $self;
}

################################################################################

=item $self = $self->_update_media()

Preforms the SQL that updates the media table

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub _update_media {
    my $self = shift;

    my $sql = 'UPDATE ' . TABLE . ' SET '. join(', ', map {"$_=?"} COLS) .
      ' WHERE id=? ';

    my $sth = prepare_c($sql, undef);
    execute($sth, $self->_get(FIELDS), $self->_get('id'));
    return $self;
}

################################################################################

=item $self = $self->_insert_version()

Preforms the sql that inserts a record into the media version table

=cut

sub _insert_version {
    my $self = shift;

    my $sql = 'INSERT INTO '. VERSION_TABLE .
      ' (id, '.join(', ', VERSION_COLS) . ')' .
        " VALUES (${\next_key(VERSION_TABLE)}, ".
          join(', ', ('?') x VERSION_COLS) . ')';

    my $sth = prepare_c($sql, undef);
    execute($sth, $self->_get(VERSION_FIELDS));
    $self->_set( { version_id => last_key(VERSION_TABLE) });
    return $self;
}

################################################################################

=item $self = $self->_update_version()

Preforms the sql that updates the media_version table

=cut

sub _update_version {
    my $self = shift;

    my $sql = 'UPDATE ' . VERSION_TABLE .
      ' SET ' . join(', ', map {"$_=?" } VERSION_COLS) .
        ' WHERE id=? ';

    my $sth = prepare_c($sql, undef);
    execute($sth, $self->_get(VERSION_FIELDS), $self->_get('version_id'));
    return $self;
}

################################################################################

=item $self = $self->_delete_media()

Removes the media row from the database

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub _delete_media {
    my $self = shift;

    my $sql = 'DELETE FROM ' . TABLE .
      ' WHERE id=? ';

    my $sth = prepare_c($sql, undef);
    execute($sth, $self->_get('id'));
    return $self;
}

################################################################################

=item $self = $self->_delete_version()

Removes the version row from the database

=cut

sub _delete_version {
    my $self = shift;

    my $sql = 'DELETE FROM ' . VERSION_TABLE .
      ' WHERE id=? ';

    my $sth = prepare_c($sql, undef);
    execute($sth, $self->_get('version_id'));
    return $self;
}

################################################################################

=item $self = $self->_select_media($where, @bind);

Populates the object from a database row

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub _select_media {
    my ($self, $where, @bind) = @_;
    my @d;

    my $sql = 'SELECT id,'. join(',',COLS) . " FROM ". TABLE;

    # add the where Clause
    $sql .= " WHERE $where";

    my $sth = prepare_ca($sql, undef);
    execute($sth, @bind);
    bind_columns($sth, \@d[0 .. (scalar COLS + 1)]);
    fetch($sth);

    # set the values retrieved
    $self->_set( [ 'id', FIELDS, RO_FIELDS], [@d]);

    my $v_grp = Bric::Util::Grp::AssetVersion->lookup(
      { id => $self->_get('version_grp__id') } );
    $self->_set( { '_version_grp' => $v_grp });
    return $self;
}

################################################################################

=item $self = $self->_do_update()

Updates the row in the data base

B<Throws:> NONE.

B<Side Effects:> NONE.

B<Notes:> NONE.

=cut

sub _do_update {
    my $self = shift;

    my $sql = 'UPDATE ' . TABLE . ' '.
      'SET ' . join(', ', map { "$_=?" } COLS) .
                                ' WHERE id=? ';

    my $update = prepare_c($sql, undef);
    execute($update, $self->_get( FIELDS ), $self->_get('id') );
    return $self;
}

################################################################################

=item $self = $self->_create_instance()

Creates a new instance object

=cut

sub _create_instance {
    my ($self, $ic) = @_;

    $ic = $ic->get_id if ref $ic;

    my $instance = Bric::Biz::Asset::Business::Parts::Instance::Media->new
        ({ element          => $self->_get('_element_object'),
           element__id      => $self->_get('element__id'),
           input_channel_id => $ic });
    
    $self->add_instances($instance);
}


1;
__END__

=back

=head1 NOTES

Some additional fields may be needed here such as a field for what kind of
object this represents etc.

=head1 AUTHOR

"Michael Soderstrom" E<lt>miraso@pacbell.netE<gt>

=head1 SEE ALSO

L<perl>, L<Bric>, L<Bric::Biz::Asset>, L<Bric::Biz::Asset::Business>

=cut
