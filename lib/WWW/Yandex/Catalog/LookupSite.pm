package WWW::Yandex::Catalog::LookupSite;

# Last updated July 24, 2014
#
# Author:       Irakliy Sunguryan ( www.sochi-travel.info )
# Date Created: January 30, 2010

use strict;
use warnings;

use vars qw($VERSION);
$VERSION    = '0.10';

use LWP::UserAgent;

my $HAS_PUNYMOD;
BEGIN { $HAS_PUNYMOD = eval 'use URI::UTF8::Punycode; 1;'; }


sub new {
    my $class = shift;
    my %options = @_;

    my $self = {
        _tic        => undef,
            # undef - if there was an error getting or parsing data
            # 0     - (a) when site is not present in catalog and tIC is < 10
            #       - (b) when site is present in catalog, but the catalog 
            #             reports it as zero (payed submission)
        _shortDescr => undef,
            # defined only when site is present in catalog; undef otherwise
        _longDescr  => undef,
            # can be undef when site is present in catalog!
            # not all sites in the catalog have long description
        _categories => [],
            # empty when site is not present in catalog
            # at least one entry when present in catalog
        _orderNum   => undef,
            # order number in the sub-category of catalog; "main" subcategory,
            # when there are more than one.
            # defined only when site is present in the catalog; undef otherwise
        _uri        => undef,
            # URI as it is recorded in catalog. for example with/without 'www' prefix
            # or it can be recorded with totally different address (narod.ru -> narod.yandex.ru)
            # defined only when site is present in catalog; undef otherwise
    };
    
    # first get module's options...
    $self->{puny2uni} = exists $options{puny2uni} ? delete $options{puny2uni} : 1;   # default value is 1
    warn 'This option requires URI::UTF8::Punycode module.' 
        if $self->{puny2uni} and !$HAS_PUNYMOD;

    $self->{ua} = LWP::UserAgent->new( agent => __PACKAGE__ . "/" . $VERSION );

    # ...the rest are LWP::UserAgent options
    foreach my $option ( keys %options ) {
        $self->{ua}->$option( $options{$option} );
    }
    
    bless $self, $class;
    return $self;
}


# Returns [ tIC, short description, long description, [list of catalogs], URI as returned by Yaca, order number in the main category ]
# "yaca" - Yandex Catalog
sub yaca_lookup {
    my $self = shift;

    my $address = shift || return;

    # an $address is nomally a domain name (whatever level), but can include path too.
    # scheme, authentication, port, and query strings are stripped --
    #   assuming Yandex won't accept URIs that contain all this

    $self->{_tic} = $self->{_shortDescr} = $self->{_longDescr} = $self->{_orderNum} = $self->{_uri} = undef;
    $self->{_categories} = [];

    $address =~ s|.*?://||;       # loose scheme
    $address =~ s|.*?(:.*?)?@||;  # loose authentication
    $address =~ s|(\w):\d+|$1|;   # loose port
    $address =~ s|\?.*||;         # loose query
    $address =~ s|/$||;           # loose trailing slash

    my $resp = $self->{ua}->get( 'http://yaca.yandex.ru/yca/cy/ch/' . $address . '/' );
    return unless $resp->is_success;
    
    my $contents = $resp->decoded_content;
    
    if( $contents =~ /<p class="b-cy_error-cy">/ ) {
        # "ресурс не описан в Яндекс.Каталоге"
        # It's not in the catalog, but tIC is always displayed.
        # Ex.: Индекс цитирования (тИЦ) ресурса — 10
        ( $self->{_tic} ) = $contents =~ /<p class="b-cy_error-cy">.*?\s(\d+)/s;
        $self->{_tic} = 0 unless defined $self->{_tic};
        }
    else {
        my( $entry ) = $contents =~ qr{(<tr>\s*<td><img.*/arr-hilite\.gif".*?</tr>)}s;
        
        ( $self->{_orderNum}, $self->{_uri}, $self->{_shortDescr}, undef, $self->{_longDescr}, $self->{_tic} ) = 
            #                  $1                       $2        $3            $4             $5
            $entry =~ qr{<td>(\d+)\.\s*</td>.*<a href="(.*?)".*?>(.*)</a>(<div>(.*)</div>.*?)?(\d+)<}s;

        $self->{_uri} = $self->process_idn( $self->{_uri} );
        
        # main catalog
        my( $path, $rubric ) = $contents =~ qr{<div class="b-path">(.*?)</div>\s*<h1.*?><a.*?>(.*?)</a>}s;
        if( $path ) {
            $path =~ s{</?a.*?>|</?h1>|\n}{}gs; # remove A, H1 tags and newline
            $path =~ s|\x{0420}\x{0443}\x{0431}\x{0440}\x{0438}\x{043A}\x{0438} / ||;
                # removed "Рубрики" - it always starts with this root word
                # http://www.rishida.net/tools/conversion/
            push( @{$self->{_categories}}, $path.' / '.$rubric ) if $entry;
        }

        # additional catalogs
        ( $entry ) = $contents =~ qr{<div class="b-cy_links">(.*?)</div>}s;
        if( $entry ) {
            while( $entry =~ s{<a.*?>(.*?)</a></p>.*?(<a|$)}{$2}s ) {
                my $catPath = $1;
                $catPath =~ s|\x{041A}\x{0430}\x{0442}\x{0430}\x{043B}\x{043E}\x{0433} / ||;
                    # removed "Каталог" - we know it's in the catalog
                push( @{$self->{_categories}}, $catPath ) if $catPath;
            }
        }
    }

    return [ $self->{_tic}, $self->{_shortDescr}, $self->{_longDescr}, $self->{_categories}, $self->{_uri}, $self->{_orderNum} ];
}

# Converts punycode in a URL to utf8, if required by options.
# Returns converted URL. Or original if conversion module is not installed.
sub process_idn {
    my( $self, $uri ) = @_;
    
    # return what we got if puny2uni was not requested, or module is not installed
    return $uri unless $self->{puny2uni} and $HAS_PUNYMOD;
    
    s/^\s+//, s/\s+$// for $uri; # trim $uri just in case
    my( $schema, $domain, $path ) = $uri =~ m{(http.*?//)(.*?)(($|/|:).*)};
        # Ex.: http://www.domain.com:80/path?quary#anchor -> 'http://' , 'www.domain.com' , ':80/path?quary#anchor'
        # I hope there are no urls with username/password links in YaCa
        # I hope there are no non-http(s) links in YaCa
        # I hope all links include schema part
        # Anyway, from awhat I've seen so far we should be Ok.
    
    $domain = join( '.', map { /^xn--/ ? puny_dec($_) : $_ } split(/\./, $domain) );
        # split by dot -> convert only punycode parts -> glue 'em back together

    return $schema.$domain.$path;
}

# == Convenience functions =================================

sub is_in_catalog {
    my $self = shift;
    return scalar @{$self->{_categories}} > 0 ? 1 : 0;
}

sub tic {
    my $self = shift;
    return $self->{_tic};
}

sub short_description {
    my $self = shift;
    return $self->{_shortDescr};
}

sub long_description {
    my $self = shift;
    return $self->{_longDescr};
}

sub categories {
    my $self = shift;
    return $self->{_categories};
}

sub order_number {
    my $self = shift;
    return $self->{_orderNum};
}

sub uri {
    my $self = shift;
    return $self->{_uri};
}

1;

__END__

=encoding utf8

=head1 NAME

WWW::Yandex::Catalog::LookupSite - Query Yandex Catalog for a website's presence, it's Index of Citing, descriptions in the catalog, and the list of categories it belongs to.

=head1 SYNOPSIS

    use WWW::Yandex::Catalog::LookupSite;

    my $site = WWW::Yandex::Catalog::LookupSite->new();

    $site->yaca_lookup('www.slovnik.org');

    print $site->tic . "\n";
    print $site->short_description . "\n";
    print $site->long_description . "\n";
    print "$_\n" foreach @{$site->categories};


=head1 DESCRIPTION

The C<WWW::Yandex::Catalog::LookupSite> module retrieves website's Thematic Index of Citing, and checks website's presence in Yandex Catalog, retrieves it's descriptions as recorded in the catalog, and the list of categories it belongs to.

This module uses C<LWP::Simple> for making requests to Yandex Catalog.

=head2 Data retrieved

I<Thematic Index of Citing (tIC)> is technology of Yandex similar to Google's Page Rank. The tIC value's step is 10, so when tIC is under 10, this module will return 0.

Each website in the Yandex Catalog has I<short description>.

I<Not> every website in the Yandex Catalog has I<long description>.

Every website in the Yandex Catalog will belong to at least one I<category>. It may belong to several other categories as well.

Yandex Catalog may know the website by different I<uri>.

We also know the I<order number> (position) of the site in the main catogory where it is listed.


=head1 CONSTRUCTOR

=head2 WWW::Yandex::Catalog::LookupSite->new()

Creates and returns a new C<WWW::Yandex::Catalog::LookupSite> object.

    my $site = WWW::Yandex::Catalog::LookupSite->new();


=head1 DATA-FETCHING METHODS

=head2 $site-E<gt>yaca_lookup( $uri )

Given a URL/URI, strips unnessesary data from it (scheme, authentication, port, and query), fetches Yandex Catalog with it, and parses results for data.

Returns an array ref to: C<[ tIC, short description, long description, [ catalogs ], uri, ordinal number ]>.
Returns C<undef> if couldn't fetch the URI.

Short and long description are returned as provided by Yandex, in UTF8 encoding.

Catalogs is an array of strings in format similar to "C<Auto & Moto / Motorcycles / Yamaha>". The leading "C<Catalog / >" is striped, I don't believe there're any sites in root of the Catalog.

C<uri> is returned as stored in the Catalog, which can be defferent from the input URI. For example, with/without C<www> prefix, or even completely different address (C<www.narod.ru -E<gt> narod.yandex.ru>).

The listing number in the main catogory. Note, that only order in the main catogory is available. For any additional categories this information is currently not provided.

=over 1

=item B<tIC>

C<undef> - if there was an error getting or parsing data.
Numeric string with tIC value otherwise. This value (zero or greater, with 10 points step) is always returned. tIC value of zero indicates that eihter site's tIC value is really very low (under 10), or that such site does not exist.

=item B<Short Description>

Returned only when site is present in the Catalog (in UTF8 encoding); C<undef> otherwise.

=item B<Long Description>

Can be C<undef> when site is present in the Catalog -- not all sites in the catalog have long description. Returned in UTF8 encoding.

=item B<Categories>

Empty list is returned when site is not present in Catalog. At least one entry when present in the catalog.

=item B<URI>

Address as stored in the Catalog (see notes above).

=item B<Ordinal number>

Returned only when site is present in catalog; C<undef> otherwise.

=back


=head1 CONVENIENCE METHODS

These methods can be called only after C<$site-E<gt>yaca_lookup( $uri )>

=head2 $site-E<gt>is_in_catalog

Returns C<1> if any categories has been retrieved; C<0> otherwise.

=head2 $site-E<gt>tic

=for comment
Self explanatory. This comment is here to shut the podchecker up.

=head2 $site-E<gt>short_description

=for comment
Self explanatory. This comment is here to shut the podchecker up.

=head2 $site-E<gt>long_description

=for comment
Self explanatory. This comment is here to shut the podchecker up.

=head2 $site-E<gt>categories

    print $site->tic . "\n";
    if( $site->is_in_catalog ) {
        print $site->short_description . "\n";
        print $site->long_description . "\n";
        print "$_\n" foreach @{$site->categories};
    }

=head2 $site-E<gt>uri

=for comment
Self explanatory. This comment is here to shut the podchecker up.

=head2 $site-E<gt>order_number

=for comment
Self explanatory. This comment is here to shut the podchecker up.


=head1 AUTHOR

Irakliy Sunguryan, L<http://www.slovnik.org/>


=head1 DEVELOPMENT & BUGS

Repository: L<https://github.com/OpossumPetya/WWW-Yandex-Catalog-LookupSite>.

Please report any bugs at L<GitHub|https://github.com/OpossumPetya/WWW-Yandex-Catalog-LookupSite/issues>, L<RT|http://rt.cpan.org/NoAuth/ReportBug.html?Queue=WWW-Yandex-Catalog-LookupSite>, or via email C<bug-www-yandex-catalog-lookupsite at rt.cpan.org>.


=head1 LICENSE AND COPYRIGHT

Copyright 2010-2012 Irakliy Sunguryan.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

=cut