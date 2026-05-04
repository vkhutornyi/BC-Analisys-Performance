namespace Ciellos.Test.Tooling;

using Microsoft.Inventory.Location;
using Microsoft.Foundation.NoSeries;

table 99050 "BCPT Data Gen. Setup"
{
    Caption = 'BCPT Data Gen. Setup';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Primary Key"; Code[10])
        {
            Caption = 'Primary Key';
        }
        field(10; "No. of Items"; Integer)
        {
            Caption = 'No. of Items to Create';
            MinValue = 0;
            InitValue = 1000;
        }
        field(11; "No. of SN Items"; Integer)
        {
            Caption = 'No. of Items with S/N Tracking';
            MinValue = 0;
            InitValue = 100;
        }
        field(20; "No. of IJ Lines No SN"; Integer)
        {
            Caption = 'No. of Item Journal Lines (No S/N)';
            MinValue = 0;
            InitValue = 1000;
        }
        field(21; "No. of IJ Lines SN"; Integer)
        {
            Caption = 'No. of Item Journal Lines (S/N)';
            MinValue = 0;
            InitValue = 100;
        }
        field(30; "No. of Sales Invoices"; Integer)
        {
            Caption = 'No. of Sales Invoices to Create';
            MinValue = 0;
            InitValue = 100;
        }
        field(31; "Lines per Invoice"; Integer)
        {
            Caption = 'No. of Lines per Invoice';
            MinValue = 1;
            InitValue = 10;
        }
        field(40; "Location Code"; Code[10])
        {
            Caption = 'Location Code for Item Journal';
            TableRelation = Location;
        }
        field(41; "SN No. Series"; Code[20])
        {
            Caption = 'No. Series for Serial Numbers';
            TableRelation = "No. Series";
        }
        field(50; "Items Generated"; Integer)
        {
            Caption = 'Items Generated (Progress)';
            MinValue = 0;
            Editable = false;
        }
        field(51; "SN Items Generated"; Integer)
        {
            Caption = 'S/N Items Generated (Progress)';
            MinValue = 0;
            Editable = false;
        }
        field(52; "IJ No SN Posted"; Boolean)
        {
            Caption = 'Item Journal (No S/N) Posted';
            Editable = false;
        }
        field(53; "IJ SN Posted"; Boolean)
        {
            Caption = 'Item Journal (S/N) Posted';
            Editable = false;
        }
        field(54; "Sales Invoices Posted"; Integer)
        {
            Caption = 'Sales Invoices Posted (Progress)';
            MinValue = 0;
            Editable = false;
        }
        field(55; "Start from Scratch"; Boolean)
        {
            Caption = 'Start from Scratch';
        }
    }

    keys
    {
        key(PK; "Primary Key") { Clustered = true; }
    }

    procedure GetOrCreate(): Record "BCPT Data Gen. Setup"
    var
        Setup: Record "BCPT Data Gen. Setup";
    begin
        if not Setup.Get('') then begin
            Setup.Init();
            Setup."Primary Key" := '';
            Setup."No. of Items" := 1000;
            Setup."No. of SN Items" := 100;
            Setup."No. of IJ Lines No SN" := 1000;
            Setup."No. of IJ Lines SN" := 100;
            Setup."No. of Sales Invoices" := 1000;
            Setup."Lines per Invoice" := 1000;
            Setup.Insert(true);
        end;
        exit(Setup);
    end;

    procedure ResetProgress()
    var
        Setup: Record "BCPT Data Gen. Setup";
    begin
        if not Setup.Get('') then
            exit;
        Setup."Items Generated" := 0;
        Setup."SN Items Generated" := 0;
        Setup."IJ No SN Posted" := false;
        Setup."IJ SN Posted" := false;
        Setup."Sales Invoices Posted" := 0;
        Setup."Start from Scratch" := false;
        Setup.Modify(true);
    end;
}
