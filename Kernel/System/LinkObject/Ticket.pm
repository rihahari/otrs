# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::LinkObject::Ticket;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Log',
    'Kernel::System::Ticket',
    'Kernel::System::SysConfig',
);

=head1 NAME

Kernel::System::LinkObject::Ticket

=head1 DESCRIPTION

Ticket backend for the ticket link object.

=head1 PUBLIC INTERFACE

=head2 new()

Don't use the constructor directly, use the ObjectManager instead:

    my $LinkObjectTicketObject = $Kernel::OM->Get('Kernel::System::LinkObject::Ticket');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=head2 LinkListWithData()

fill up the link list with data

    $Success = $LinkObjectBackend->LinkListWithData(
        LinkList                     => $HashRef,
        IgnoreLinkedTicketStateTypes => 0|1,        # (optional) default 0
        UserID                       => 1,
    );

=cut

sub LinkListWithData {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(LinkList UserID)) {
        if ( !$Param{$Argument} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );
            return;
        }
    }

    # check link list
    if ( ref $Param{LinkList} ne 'HASH' ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'LinkList must be a hash reference!',
        );
        return;
    }

    # get ticket object
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    # get config, which ticket state types should not be included in linked tickets overview
    my @IgnoreLinkedTicketStateTypes = @{
        $Kernel::OM->Get('Kernel::Config')->Get('LinkObject::IgnoreLinkedTicketStateTypes')
            // []
    };

    my %IgnoreLinkTicketStateTypesHash;
    map { $IgnoreLinkTicketStateTypesHash{$_}++ } @IgnoreLinkedTicketStateTypes;

    for my $LinkType ( sort keys %{ $Param{LinkList} } ) {

        for my $Direction ( sort keys %{ $Param{LinkList}->{$LinkType} } ) {

            TICKETID:
            for my $TicketID ( sort keys %{ $Param{LinkList}->{$LinkType}->{$Direction} } ) {

                # get ticket data
                my %TicketData = $TicketObject->TicketGet(
                    TicketID      => $TicketID,
                    UserID        => $Param{UserID},
                    DynamicFields => 0,
                );

                # remove id from hash if ticket can not get
                if ( !%TicketData ) {
                    delete $Param{LinkList}->{$LinkType}->{$Direction}->{$TicketID};
                    next TICKETID;
                }

                # if param is set, remove entries from hash with configured ticket state types
                if (
                    $Param{IgnoreLinkedTicketStateTypes}
                    && $IgnoreLinkTicketStateTypesHash{ $TicketData{StateType} }
                    )
                {
                    delete $Param{LinkList}->{$LinkType}->{$Direction}->{$TicketID};
                    next TICKETID;
                }

                # add ticket data
                $Param{LinkList}->{$LinkType}->{$Direction}->{$TicketID} = \%TicketData;
            }
        }
    }

    return 1;
}

=head2 ObjectPermission()

checks read permission for a given object and UserID.

    $Permission = $LinkObject->ObjectPermission(
        Object  => 'Ticket',
        Key     => 123,
        UserID  => 1,
    );

=cut

sub ObjectPermission {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(Object Key UserID)) {
        if ( !$Param{$Argument} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );
            return;
        }
    }

    return $Kernel::OM->Get('Kernel::System::Ticket')->TicketPermission(
        Type     => 'ro',
        TicketID => $Param{Key},
        UserID   => $Param{UserID},
    );
}

=head2 ObjectDescriptionGet()

return a hash of object descriptions

Return
    %Description = (
        Normal => "Ticket# 1234455",
        Long   => "Ticket# 1234455: The Ticket Title",
    );

    %Description = $LinkObject->ObjectDescriptionGet(
        Key     => 123,
        Mode    => 'Temporary',  # (optional)
        UserID  => 1,
    );

=cut

sub ObjectDescriptionGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(Object Key UserID)) {
        if ( !$Param{$Argument} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );
            return;
        }
    }

    # create description
    my %Description = (
        Normal => 'Ticket',
        Long   => 'Ticket',
    );

    return %Description if $Param{Mode} && $Param{Mode} eq 'Temporary';

    # get ticket
    my %Ticket = $Kernel::OM->Get('Kernel::System::Ticket')->TicketGet(
        TicketID      => $Param{Key},
        UserID        => $Param{UserID},
        DynamicFields => 0,
    );

    return if !%Ticket;

    my $ParamHook = $Kernel::OM->Get('Kernel::Config')->Get('Ticket::Hook') || 'Ticket#';
    $ParamHook .= $Kernel::OM->Get('Kernel::Config')->Get('Ticket::HookDivider') || '';

    # create description
    %Description = (
        Normal => $ParamHook . "$Ticket{TicketNumber}",
        Long   => $ParamHook . "$Ticket{TicketNumber}: $Ticket{Title}",
    );

    return %Description;
}

=head2 ObjectSearch()

return a hash list of the search results

Returns:

    $SearchList = {
        NOTLINKED => {
            Source => {
                12  => $DataOfItem12,
                212 => $DataOfItem212,
                332 => $DataOfItem332,
            },
        },
    };

    $SearchList = $LinkObjectBackend->ObjectSearch(
        SubObject    => 'Bla',     # (optional)
        SearchParams => $HashRef,  # (optional)
        UserID       => 1,
    );

=cut

sub ObjectSearch {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{UserID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need UserID!',
        );
        return;
    }

    # set default params
    $Param{SearchParams} ||= {};

    # set focus
    my %Search;
    if ( $Param{SearchParams}->{TicketFulltext} ) {
        %Search = (
            From          => '*' . $Param{SearchParams}->{TicketFulltext} . '*',
            To            => '*' . $Param{SearchParams}->{TicketFulltext} . '*',
            Cc            => '*' . $Param{SearchParams}->{TicketFulltext} . '*',
            Subject       => '*' . $Param{SearchParams}->{TicketFulltext} . '*',
            Body          => '*' . $Param{SearchParams}->{TicketFulltext} . '*',
            ContentSearch => 'OR',
        );
    }
    if ( $Param{SearchParams}->{TicketTitle} ) {
        $Search{Title} = '*' . $Param{SearchParams}->{TicketTitle} . '*';
    }

    if ( IsArrayRefWithData( $Param{SearchParams}->{ArchiveID} ) ) {
        if ( $Param{SearchParams}->{ArchiveID}->[0] eq 'AllTickets' ) {
            $Search{ArchiveFlags} = [ 'y', 'n' ];
        }
        elsif ( $Param{SearchParams}->{ArchiveID}->[0] eq 'NotArchivedTickets' ) {
            $Search{ArchiveFlags} = ['n'];
        }
        elsif ( $Param{SearchParams}->{ArchiveID}->[0] eq 'ArchivedTickets' ) {
            $Search{ArchiveFlags} = ['y'];
        }
    }

    # get ticket object
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    # search the tickets
    my @TicketIDs = $TicketObject->TicketSearch(
        %{ $Param{SearchParams} },
        %Search,
        Limit               => 50,
        Result              => 'ARRAY',
        ConditionInline     => 1,
        ContentSearchPrefix => '*',
        ContentSearchSuffix => '*',
        FullTextIndex       => 1,
        OrderBy             => 'Down',
        SortBy              => 'Age',
        UserID              => $Param{UserID},
    );

    my %SearchList;
    TICKETID:
    for my $TicketID (@TicketIDs) {

        # get ticket data
        my %TicketData = $TicketObject->TicketGet(
            TicketID      => $TicketID,
            UserID        => $Param{UserID},
            DynamicFields => 0,
        );

        next TICKETID if !%TicketData;

        # add ticket data
        $SearchList{NOTLINKED}->{Source}->{$TicketID} = \%TicketData;
    }

    return \%SearchList;
}

=head2 LinkAddPre()

link add pre event module

    $True = $LinkObject->LinkAddPre(
        Key          => 123,
        SourceObject => 'Ticket',
        SourceKey    => 321,
        Type         => 'Normal',
        State        => 'Valid',
        UserID       => 1,
    );

    or

    $True = $LinkObject->LinkAddPre(
        Key          => 123,
        TargetObject => 'Ticket',
        TargetKey    => 321,
        Type         => 'Normal',
        State        => 'Valid',
        UserID       => 1,
    );

=cut

sub LinkAddPre {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(Key Type State UserID)) {
        if ( !$Param{$Argument} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );
            return;
        }
    }

    return 1 if $Param{State} eq 'Temporary';

    return 1;
}

=head2 LinkAddPost()

link add pre event module

    $True = $LinkObject->LinkAddPost(
        Key          => 123,
        SourceObject => 'Ticket',
        SourceKey    => 321,
        Type         => 'Normal',
        State        => 'Valid',
        UserID       => 1,
    );

    or

    $True = $LinkObject->LinkAddPost(
        Key          => 123,
        TargetObject => 'Ticket',
        TargetKey    => 321,
        Type         => 'Normal',
        State        => 'Valid',
        UserID       => 1,
    );

=cut

sub LinkAddPost {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(Key Type State UserID)) {
        if ( !$Param{$Argument} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );
            return;
        }
    }

    return 1 if $Param{State} eq 'Temporary';

    # get ticket object
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    if ( $Param{SourceObject} && $Param{SourceObject} eq 'Ticket' && $Param{SourceKey} ) {

        # lookup ticket number
        my $TicketNumber = $TicketObject->TicketNumberLookup(
            TicketID => $Param{SourceKey},
            UserID   => $Param{UserID},
        );

        # add ticket history entry
        $TicketObject->HistoryAdd(
            TicketID     => $Param{Key},
            CreateUserID => $Param{UserID},
            HistoryType  => 'TicketLinkAdd',
            Name         => "\%\%$TicketNumber\%\%$Param{SourceKey}\%\%$Param{Key}",
        );

        # ticket event
        $TicketObject->EventHandler(
            Event => 'TicketSourceLinkAdd' . $Param{Type},
            Data  => {
                TicketID => $Param{Key},
            },
            UserID => $Param{UserID},
        );

        return 1;
    }

    if ( $Param{TargetObject} && $Param{TargetObject} eq 'Ticket' && $Param{TargetKey} ) {

        # lookup ticket number
        my $TicketNumber = $TicketObject->TicketNumberLookup(
            TicketID => $Param{TargetKey},
            UserID   => $Param{UserID},
        );

        # add ticket history entry
        $TicketObject->HistoryAdd(
            TicketID     => $Param{Key},
            CreateUserID => $Param{UserID},
            HistoryType  => 'TicketLinkAdd',
            Name         => "\%\%$TicketNumber\%\%$Param{TargetKey}\%\%$Param{Key}",
        );

        # ticket event
        $TicketObject->EventHandler(
            Event  => 'TicketTargetLinkAdd' . $Param{Type},
            UserID => $Param{UserID},
            Data   => {
                TicketID => $Param{Key},
            },
        );

        return 1;
    }

    return 1;
}

=head2 LinkDeletePre()

link delete pre event module

    $True = $LinkObject->LinkDeletePre(
        Key          => 123,
        SourceObject => 'Ticket',
        SourceKey    => 321,
        Type         => 'Normal',
        State        => 'Valid',
        UserID       => 1,
    );

    or

    $True = $LinkObject->LinkDeletePre(
        Key          => 123,
        TargetObject => 'Ticket',
        TargetKey    => 321,
        Type         => 'Normal',
        State        => 'Valid',
        UserID       => 1,
    );

=cut

sub LinkDeletePre {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(Key Type State UserID)) {
        if ( !$Param{$Argument} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );
            return;
        }
    }

    return 1 if $Param{State} eq 'Temporary';

    return 1;
}

=head2 LinkDeletePost()

link delete post event module

    $True = $LinkObject->LinkDeletePost(
        Key          => 123,
        SourceObject => 'Ticket',
        SourceKey    => 321,
        Type         => 'Normal',
        State        => 'Valid',
        UserID       => 1,
    );

    or

    $True = $LinkObject->LinkDeletePost(
        Key          => 123,
        TargetObject => 'Ticket',
        TargetKey    => 321,
        Type         => 'Normal',
        State        => 'Valid',
        UserID       => 1,
    );

=cut

sub LinkDeletePost {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Argument (qw(Key Type State UserID)) {
        if ( !$Param{$Argument} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Argument!",
            );
            return;
        }
    }

    return 1 if $Param{State} eq 'Temporary';

    # get ticket object
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    if ( $Param{SourceObject} && $Param{SourceObject} eq 'Ticket' && $Param{SourceKey} ) {

        # lookup ticket number
        my $TicketNumber = $TicketObject->TicketNumberLookup(
            TicketID => $Param{SourceKey},
            UserID   => $Param{UserID},
        );

        # add ticket history entry
        $TicketObject->HistoryAdd(
            TicketID     => $Param{Key},
            CreateUserID => $Param{UserID},
            HistoryType  => 'TicketLinkDelete',
            Name         => "\%\%$TicketNumber\%\%$Param{SourceKey}\%\%$Param{Key}",
        );

        # ticket event
        $TicketObject->EventHandler(
            Event => 'TicketSourceLinkDelete' . $Param{Type},
            Data  => {
                TicketID => $Param{Key},
            },
            UserID => $Param{UserID},
        );

        return 1;
    }

    if ( $Param{TargetObject} && $Param{TargetObject} eq 'Ticket' && $Param{TargetKey} ) {

        # lookup ticket number
        my $TicketNumber = $TicketObject->TicketNumberLookup(
            TicketID => $Param{TargetKey},
            UserID   => $Param{UserID},
        );

        # add ticket history entry
        $TicketObject->HistoryAdd(
            TicketID     => $Param{Key},
            CreateUserID => $Param{UserID},
            HistoryType  => 'TicketLinkDelete',
            Name         => "\%\%$TicketNumber\%\%$Param{TargetKey}\%\%$Param{Key}",
        );

        # ticket event
        $TicketObject->EventHandler(
            Event => 'TicketTargetLinkDelete' . $Param{Type},
            Data  => {
                TicketID => $Param{Key},
            },
            UserID => $Param{UserID},
        );

        return 1;
    }

    return 1;
}

=head2 EventTypeConfigUpdate()

Updates the ticket event configuration based on configured link types.

    my $Success = $LinkObjectTicketObject->EventTypeConfigUpdate();

Returns true if successful.

=cut

sub EventTypeConfigUpdate {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my $LinkTypes    = $ConfigObject->Get('LinkObject::Type') || {};
    my $TicketEvents = $ConfigObject->Get('Events')->{Ticket} || [];

    # Add missing ticket events for all configured link object types.
    for my $LinkType ( sort keys %{$LinkTypes} ) {
        for my $ObjectType (qw(Source Target)) {
            for my $EventType (qw(Add Delete)) {
                my $Event = "Ticket${ObjectType}Link${EventType}$LinkType";
                if ( !grep { $_ eq $Event } @{$TicketEvents} ) {
                    push @{$TicketEvents}, $Event;
                }
            }
        }
    }

    return if !IsArrayRefWithData($TicketEvents);

    my $SettingName = 'Events###Ticket';

    # If called from a unit test, use passed unit test helper object to change the settings.
    if ( $Param{Helper} ) {
        return $Param{Helper}->ConfigSettingChange(
            Valid => 1,
            Key   => $SettingName,
            Value => $TicketEvents,
        );
    }

    my $SysConfigObject = $Kernel::OM->Get('Kernel::System::SysConfig');

    # Otherwise, retrieve the effective setting value from SysConfig.
    my %Setting = $SysConfigObject->SettingGet(
        Name     => $SettingName,
        Deployed => 1,
    );
    return if !IsHashRefWithData( \%Setting );

    $Setting{EffectiveValue} = $TicketEvents;

    # Lock the setting to admin user.
    my $ExclusiveLockGUID = $SysConfigObject->SettingLock(
        Name   => $SettingName,
        Force  => 1,
        UserID => 1,
    );
    $Setting{ExclusiveLockGUID} = $ExclusiveLockGUID;

    # Update the setting.
    my %UpdateSuccess = $SysConfigObject->SettingUpdate(
        %Setting,
        UserID => 1,
    );

    if ( !$UpdateSuccess{Success} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => $UpdateSuccess{Error} // "Error while updating $SettingName!",
        );

        # Unlock the setting.
        $SysConfigObject->SettingUnlock(
            Name => $SettingName,
        );

        return;
    }

    # Deploy the configuration.
    return $SysConfigObject->ConfigurationDeploy(
        Comments      => "$SettingName Configuration Updated",
        DirtySettings => [$SettingName],
        UserID        => 1,
        Force         => 1,
    );
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
