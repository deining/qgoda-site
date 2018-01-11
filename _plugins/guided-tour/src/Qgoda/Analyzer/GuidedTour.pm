#! /bin/false

package Qgoda::Analyzer::GuidedTour;

use strict;

use YAML::XS;
use Storable qw(dclone);

use Qgoda::Util qw(empty read_file);

use base qw(Qgoda::Analyzer);

sub setup {
    my ($self, $site) = @_;

    my $config_file = '_guided_tour.yaml';
    my $yaml = read_file $config_file
        or die "cannot open '$config_file' for reading: $!\n";
    my $tours = YAML::XS::Load($yaml);
    my $sections = $tours->{sections};

    my %sections;
    my %docs;
    my $secorder = 0;
    my $order = 0;
    foreach my $section (@$sections) {
        my ($name, @docs) = @$section;
        $sections{$name} = {
            title => $name,
            name => $name,
            order => ++$secorder,
        };

        my $docorder = 0;
        foreach my $doc (@docs) {
            $docs{$doc} = $sections{$name}->{docs}->{$doc} = {
                title => $doc,
                order => ++$docorder,
                section => $name,
            };
        }
    }

    my $linguas = $site->{config}->{linguas} || [''];
    my %tree;
    foreach my $lingua (@$linguas) {
        $tree{$lingua} = dclone \%sections;
    }

    foreach my $asset ($site->getAssets) {
        next if 'doc' ne $asset->{type};
        if ($asset->{virtual}) {
            # Retrieve the real title.
            my $lingua = $asset->{lingua} || '';
            my $name = $asset->{name};
            $tree{$lingua}->{$name}->{title} = $asset->{title}
        } elsif (!empty $asset->{section}) {
            my $section_name = $asset->{section};
            my $lingua = $asset->{lingua} || '';
            my $name = $asset->{name};
            $tree{$lingua}->{$section_name}->{name} = $section_name;
            $tree{$lingua}->{$section_name}->{docs}->{$name}->{asset} = $asset;
            $tree{$lingua}->{$section_name}->{title} = $section_name
                if empty $tree{$lingua}->{$section_name}->{title};
            $tree{$lingua}
                ->{$section_name}
                ->{docs}
                ->{$name}
                ->{title} = $asset->{title};
            $tree{$lingua}
                ->{$section_name}
                ->{docs}
                ->{$name}
                ->{section} = $section_name;            
        } elsif ('documentation' eq $asset->{name}) {
            my $lingua = $asset->{lingua} || '';
            $self->{__start}->{$lingua} = $asset;
        }
    }

    my %navigation;
    my %tours;
    foreach my $lingua (keys %tree) {
        my $data = $tree{$lingua};
        my @sections;
        my @tour = ($self->{__start}->{$lingua} || {});
        foreach my $name (sort { 
                $data->{$a}->{order} <=> $data->{$b}->{order} 
            } keys %$data) {
            my @docs;
            my $docs = $data->{$name}->{docs};
            foreach my $doc (sort { 
                    $docs->{$a}->{order} <=> $docs->{$b}->{order}
                } keys %$docs) {
                push @docs, $docs->{$doc};
                push @tour, $docs->{$doc}->{asset};
            }
            $data->{$name}->{docs} = \@docs;
            push @sections, $data->{$name};
        }
        $navigation{$lingua} = \@sections;

        my $prev;
        while (@tour) {
            my $asset = shift @tour;
            $asset->{nav}->{prev} = $prev if $prev;
            $asset->{nav}->{next} = $tour[0] if @tour;

            $prev = $asset;
        }
    }

    $self->{__navigation} = \%navigation;

    return $self;
}

sub analyze {
    my ($self, $asset, $site, $include) = @_;

    return $self if 'doc' ne $asset->{type};

    my $navigation = $self->{__navigation};

    my $lingua = $asset->{lingua} || '';
    $asset->{nav}->{sections} = $navigation->{$lingua};
    my $start = $self->{__start}->{$lingua};
    if ($start!= $asset) {
        $asset->{nav}->{start} = $start;
    }

    return $self;
}

1;
