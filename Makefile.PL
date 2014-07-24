use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'WWW::Yandex::Catalog::LookupSite',
    AUTHOR              => q{Irakliy Sunguryan <webmaster@slovnik.org>},
    VERSION_FROM        => 'lib/WWW/Yandex/Catalog/LookupSite.pm',
    ABSTRACT_FROM       => 'lib/WWW/Yandex/Catalog/LookupSite.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More'          => 0,
        'LWP::UserAgent'      => 0,
        # 'URI::UTF8::Punycode' => 0, # not required, but used when installed
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'WWW-Yandex-Catalog-LookupSite-*' },
);
