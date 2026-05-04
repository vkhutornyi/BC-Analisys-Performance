namespace System.Test.Tooling;

page 99051 "BCPT Data Gen. Setup"
{
    Caption = 'BCPT Data Generator Setup';
    PageType = Card;
    SourceTable = "BCPT Data Gen. Setup";
    UsageCategory = Administration;
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            group(Items)
            {
                Caption = 'Items';

                field("No. of Items"; Rec."No. of Items")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies how many standard inventory items to create.';
                }
                field("No. of SN Items"; Rec."No. of SN Items")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies how many items with Serial Number tracking to create.';
                }
            }
            group(ItemJournal)
            {
                Caption = 'Item Journal';

                field("Location Code"; Rec."Location Code")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the location used when posting item journal lines (e.g. YELLOW, SILVER, WHITE).';
                }
                field("No. of IJ Lines No SN"; Rec."No. of IJ Lines No SN")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies how many item journal lines to create and post for standard items.';
                }
                field("No. of IJ Lines SN"; Rec."No. of IJ Lines SN")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies how many item journal lines (one per serial number) to create and post for S/N tracked items.';
                }
                field("SN No. Series"; Rec."SN No. Series")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies the No. Series used to assign serial numbers to S/N tracked items.';
                }
            }
            group(SalesInvoices)
            {
                Caption = 'Sales Invoices';

                field("No. of Sales Invoices"; Rec."No. of Sales Invoices")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies how many sales invoices to create and post.';
                }
                field("Lines per Invoice"; Rec."Lines per Invoice")
                {
                    ApplicationArea = All;
                    ToolTip = 'Specifies how many sales lines each invoice will contain.';
                }
            }
            group(Progress)
            {
                Caption = 'Progress';

                field("Start from Scratch"; Rec."Start from Scratch")
                {
                    ApplicationArea = All;
                    ToolTip = 'When enabled, all progress is reset and the generator starts from the beginning on next run.';
                }
                field("Items Generated"; Rec."Items Generated")
                {
                    ApplicationArea = All;
                    ToolTip = 'Shows how many standard items have been generated so far.';
                    Editable = false;
                    Style = Favorable;
                }
                field("SN Items Generated"; Rec."SN Items Generated")
                {
                    ApplicationArea = All;
                    ToolTip = 'Shows how many S/N tracked items have been generated so far.';
                    Editable = false;
                    Style = Favorable;
                }
                field("IJ No SN Posted"; Rec."IJ No SN Posted")
                {
                    ApplicationArea = All;
                    ToolTip = 'Indicates whether the item journal for standard items has been posted.';
                    Editable = false;
                }
                field("IJ SN Posted"; Rec."IJ SN Posted")
                {
                    ApplicationArea = All;
                    ToolTip = 'Indicates whether the item journal for S/N tracked items has been posted.';
                    Editable = false;
                }
                field("Sales Invoices Posted"; Rec."Sales Invoices Posted")
                {
                    ApplicationArea = All;
                    ToolTip = 'Shows how many sales invoices have been posted so far.';
                    Editable = false;
                    Style = Favorable;
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(RunGenerator)
            {
                Caption = 'Run Data Generator';
                ApplicationArea = All;
                Image = Start;
                ToolTip = 'Creates all items, posts item journals, and posts sales invoices based on the settings above.';

                trigger OnAction()
                var
                    DataGenerator: Codeunit "BCPT Data Generator";
                begin
                    DataGenerator.Run();
                    Message('Data generation completed successfully.');
                end;
            }
        }
    }

    trigger OnOpenPage()
    begin
        if not Rec.Get('') then begin
            Rec.GetOrCreate();
            Rec.Get('');
        end;
    end;
}
