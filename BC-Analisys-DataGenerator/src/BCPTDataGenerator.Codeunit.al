namespace Ciellos.Test.Tooling;

using Microsoft.Finance.GeneralLedger.Setup;
using Microsoft.Finance.VAT.Setup;
using Microsoft.Foundation.NoSeries;
using Microsoft.Foundation.UOM;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Journal;
using Microsoft.Inventory.Posting;
using Microsoft.Inventory.Tracking;
using Microsoft.Sales.Customer;
using Microsoft.Sales.Document;
using Microsoft.Sales.Posting;
using Microsoft.Finance.SalesTax;
using Microsoft.Sales.Setup;

codeunit 99052 "BCPT Data Generator"
{
    trigger OnRun()
    var
        Setup: Record "BCPT Data Gen. Setup";
        ItemList: List of [Code[20]];
        SNItemList: List of [Code[20]];
    begin
        Setup := Setup.GetOrCreate();

        if Setup."Start from Scratch" then begin
            Setup.ResetProgress();
            Setup := Setup.GetOrCreate();
        end;

        InitNoSeries();

        // Load items already in DB — avoids re-creating what survived a prior interrupted run
        LoadItemListFromDB('TEST-ITEM-', ItemList);
        LoadItemListFromDB('TEST-SN-', SNItemList);

        // Generate only the remaining items
        GenerateItems(Setup."No. of Items" - ItemList.Count(), ItemList);
        GenerateItemsWithSN(Setup."No. of SN Items" - SNItemList.Count(), Setup."SN No. Series", SNItemList);

        if not Setup."IJ No SN Posted" then begin
            CreateAndPostItemJournal(ItemList, Setup."No. of IJ Lines No SN", Setup."Location Code", false);
            SaveIJProgress(false);
        end;

        if not Setup."IJ SN Posted" then begin
            CreateAndPostItemJournal(SNItemList, Setup."No. of IJ Lines SN", Setup."Location Code", true);
            SaveIJProgress(true);
        end;

        CreateAndPostSalesInvoices(ItemList, Setup."No. of Sales Invoices", Setup."Lines per Invoice", Setup."Location Code");
    end;

    var
        BCPTItemNoSeriesCode: Code[20];
        BCPTSNItemNoSeriesCode: Code[20];
        BCPTSerialNoSeriesCode: Code[20];

    local procedure InitNoSeries()
    var
        SalesSetup: Record "Sales & Receivables Setup";
        NoSeriesLine: Record "No. Series Line";
        Changed: Boolean;
    begin
        // Fix the Sales Invoice No. Series to avoid running out of numbers
        SalesSetup.Get();
        SalesSetup.TestField("Invoice Nos.");
        NoSeriesLine.SetRange("Series Code", SalesSetup."Invoice Nos.");
        if NoSeriesLine.FindSet(true) then
            repeat
                if NoSeriesLine."Ending No." <> '' then begin
                    NoSeriesLine."Ending No." := '';
                    NoSeriesLine.Validate(Implementation, Enum::"No. Series Implementation"::Sequence);
                    NoSeriesLine.Modify(true);
                    Changed := true;
                end;
            until NoSeriesLine.Next() = 0;

        // Create dedicated No. Series for BCPT items so we never collide with existing item numbers
        BCPTItemNoSeriesCode := EnsureBCPTNoSeries('TEST-ITEM', 'TEST-SN', 'TEST0000001', 'TESN00000001');
        BCPTSNItemNoSeriesCode := 'TEST-SN';
        BCPTSerialNoSeriesCode := EnsureSerialNoSeries();

        if Changed then
            Commit();
    end;

    local procedure EnsureBCPTNoSeries(ItemSeriesCode: Code[20]; SNSeriesCode: Code[20]; ItemStartNo: Code[20]; SNStartNo: Code[20]): Code[20]
    var
        NoSeries: Record "No. Series";
        NoSeriesLine: Record "No. Series Line";
    begin
        if not NoSeries.Get(ItemSeriesCode) then begin
            NoSeries.Code := ItemSeriesCode;
            NoSeries.Description := 'TEST Generated Items';
            NoSeries.Insert(true);
            NoSeriesLine."Series Code" := ItemSeriesCode;
            NoSeriesLine."Line No." := 10000;
            NoSeriesLine."Starting No." := ItemStartNo;
            NoSeriesLine.Validate(Implementation, Enum::"No. Series Implementation"::Sequence);
            NoSeriesLine.Insert(true);
        end;

        if not NoSeries.Get(SNSeriesCode) then begin
            NoSeries.Code := SNSeriesCode;
            NoSeries.Description := 'TEST S/N Tracking Items';
            NoSeries.Insert(true);
            NoSeriesLine.Init();
            NoSeriesLine."Series Code" := SNSeriesCode;
            NoSeriesLine."Line No." := 10000;
            NoSeriesLine."Starting No." := SNStartNo;
            NoSeriesLine.Validate(Implementation, Enum::"No. Series Implementation"::Sequence);
            NoSeriesLine.Insert(true);
        end;

        Commit();
        exit(ItemSeriesCode);
    end;

    // Creates a No. Series for serial numbers capable of generating up to 10 million values
    local procedure EnsureSerialNoSeries(): Code[20]
    var
        NoSeries: Record "No. Series";
        NoSeriesLine: Record "No. Series Line";
        SeriesCode: Code[20];
    begin
        SeriesCode := 'TEST-SRNO';
        if NoSeries.Get(SeriesCode) then
            exit(SeriesCode);

        NoSeries.Code := SeriesCode;
        NoSeries.Description := 'BCPT Item Serial Numbers';
        NoSeries.Insert(true);

        NoSeriesLine."Series Code" := SeriesCode;
        NoSeriesLine."Line No." := 10000;
        NoSeriesLine."Starting No." := 'TESN000000001';  // 9 digits → up to SN010000000 = 10 M values
        NoSeriesLine."Ending No." := 'TESN010000000';
        NoSeriesLine.Validate(Implementation, Enum::"No. Series Implementation"::Sequence);
        NoSeriesLine.Insert(true);
        Commit();

        exit(SeriesCode);
    end;

    // Loads item numbers already created in a prior run, identified by Description prefix
    local procedure LoadItemListFromDB(DescriptionPrefix: Text[30]; var ItemList: List of [Code[20]])
    var
        Item: Record Item;
    begin
        Item.SetFilter(Description, DescriptionPrefix + '*');
        Item.SetLoadFields("No.");
        if Item.FindSet() then
            repeat
                ItemList.Add(Item."No.");
            until Item.Next() = 0;
    end;

    // Saves progress counter after item generation
    local procedure SaveItemProgress(IsSnItems: Boolean; Count: Integer)
    var
        Setup: Record "BCPT Data Gen. Setup";
    begin
        if not Setup.Get('') then
            exit;
        if IsSnItems then
            Setup."SN Items Generated" := Setup."SN Items Generated" + Count
        else
            Setup."Items Generated" := Setup."Items Generated" + Count;
        Setup.Modify(true);
        Commit();
    end;

    // Marks an item journal step as done
    local procedure SaveIJProgress(IsSN: Boolean)
    var
        Setup: Record "BCPT Data Gen. Setup";
    begin
        if not Setup.Get('') then
            exit;
        if IsSN then
            Setup."IJ SN Posted" := true
        else
            Setup."IJ No SN Posted" := true;
        Setup.Modify(true);
        Commit();
    end;

    // Saves the running count of posted sales invoices
    local procedure SaveSalesProgress(TotalPosted: Integer)
    var
        Setup: Record "BCPT Data Gen. Setup";
    begin
        if not Setup.Get('') then
            exit;
        Setup."Sales Invoices Posted" := TotalPosted;
        Setup.Modify(true);
        Commit();
    end;

    // Step 1: Create standard inventory items
    local procedure GenerateItems(Count: Integer; var ItemList: List of [Code[20]])
    var
        Item: Record Item;
        UnitOfMeasure: Record "Unit of Measure";
        ItemUnitOfMeasure: Record "Item Unit of Measure";
        NoSeriesSingle: Codeunit "No. Series";
        GenProdPostingGroup: Code[20];
        InvPostingGroup: Code[20];
        VATProdPostingGroup: Code[20];
        StartIdx: Integer;
        i: Integer;
    begin
        if Count <= 0 then
            exit;

        UnitOfMeasure.FindFirst();
        GenProdPostingGroup := GetGenProdPostingGroup();
        InvPostingGroup := GetInventoryPostingGroup();
        VATProdPostingGroup := GetVATProdPostingGroup();

        // Offset the description index so resumed items continue the sequence correctly
        StartIdx := ItemList.Count() + 1;

        for i := 1 to Count do begin
            Item.Init();
            Item."No." := NoSeriesSingle.GetNextNo(BCPTItemNoSeriesCode, WorkDate(), true);
            Item.Insert(true);

            ItemUnitOfMeasure.Init();
            ItemUnitOfMeasure.Validate("Item No.", Item."No.");
            ItemUnitOfMeasure.Validate(Code, UnitOfMeasure.Code);
            ItemUnitOfMeasure.Validate("Qty. per Unit of Measure", 1);
            ItemUnitOfMeasure.Insert(true);

            Item.Validate(Description, 'TEST-ITEM-' + Format(StartIdx + i - 1));
            Item.Validate("Base Unit of Measure", UnitOfMeasure.Code);
            Item.Validate("Gen. Prod. Posting Group", GenProdPostingGroup);
            Item.Validate("Inventory Posting Group", InvPostingGroup);
            Item.Validate("VAT Prod. Posting Group", VATProdPostingGroup);
            Item.Modify(true);

            ItemList.Add(Item."No.");

            if i mod 100 = 0 then begin
                SaveItemProgress(false, 100);
                Commit();
            end;
        end;

        // Save any remainder not covered by the mod-100 checkpoints
        SaveItemProgress(false, Count mod 100);
        Commit();
    end;

    // Step 2: Create items with Serial Number tracking
    local procedure GenerateItemsWithSN(Count: Integer; SNNoSeries: Code[20]; var SNItemList: List of [Code[20]])
    var
        Item: Record Item;
        UnitOfMeasure: Record "Unit of Measure";
        ItemUnitOfMeasure: Record "Item Unit of Measure";
        ItemTrackingCode: Record "Item Tracking Code";
        NoSeriesSingle: Codeunit "No. Series";
        GenProdPostingGroup: Code[20];
        InvPostingGroup: Code[20];
        VATProdPostingGroup: Code[20];
        StartIdx: Integer;
        i: Integer;
    begin
        if Count <= 0 then
            exit;

        UnitOfMeasure.FindFirst();
        FindOrCreateSNTrackingCode(ItemTrackingCode);
        GenProdPostingGroup := GetGenProdPostingGroup();
        InvPostingGroup := GetInventoryPostingGroup();
        VATProdPostingGroup := GetVATProdPostingGroup();

        StartIdx := SNItemList.Count() + 1;

        for i := 1 to Count do begin
            Item.Init();
            Item."No." := NoSeriesSingle.GetNextNo(BCPTSNItemNoSeriesCode, WorkDate(), true);
            Item.Insert(true);

            ItemUnitOfMeasure.Init();
            ItemUnitOfMeasure.Validate("Item No.", Item."No.");
            ItemUnitOfMeasure.Validate(Code, UnitOfMeasure.Code);
            ItemUnitOfMeasure.Validate("Qty. per Unit of Measure", 1);
            ItemUnitOfMeasure.Insert(true);

            Item.Validate(Description, 'TEST-SN-' + Format(StartIdx + i - 1));
            Item.Validate("Base Unit of Measure", UnitOfMeasure.Code);
            Item.Validate("Item Tracking Code", ItemTrackingCode.Code);
            Item.Validate("Serial Nos.", BCPTSerialNoSeriesCode);
            Item.Validate("Gen. Prod. Posting Group", GenProdPostingGroup);
            Item.Validate("Inventory Posting Group", InvPostingGroup);
            Item.Validate("VAT Prod. Posting Group", VATProdPostingGroup);
            Item.Modify(true);

            SNItemList.Add(Item."No.");

            if i mod 50 = 0 then begin
                SaveItemProgress(true, 50);
                Commit();
            end;
        end;

        SaveItemProgress(true, Count mod 50);
        Commit();
    end;

    local procedure FindOrCreateSNTrackingCode(var ItemTrackingCode: Record "Item Tracking Code")
    begin
        ItemTrackingCode.SetRange("SN Specific Tracking", true);
        if ItemTrackingCode.FindFirst() then begin
            ItemTrackingCode.SetRange("SN Specific Tracking");
            exit;
        end;

        ItemTrackingCode.Init();
        ItemTrackingCode.Code := 'TEST-SN';
        ItemTrackingCode.Description := 'TEST Serial No. Tracking';
        ItemTrackingCode."SN Specific Tracking" := true;
        ItemTrackingCode."SN Sales Outbound Tracking" := true;
        ItemTrackingCode."SN Purchase Inbound Tracking" := true;
        ItemTrackingCode."SN Pos. Adjmt. Inb. Tracking" := true;
        ItemTrackingCode."SN Neg. Adjmt. Outb. Tracking" := true;
        ItemTrackingCode.Insert(true);
        Commit();
    end;

    // Steps 3 & 4: Create and post item journal (with or without S/N tracking)
    local procedure CreateAndPostItemJournal(ItemList: List of [Code[20]]; LineCount: Integer; LocationCode: Code[10]; WithSN: Boolean)
    var
        ItemJournalBatch: Record "Item Journal Batch";
        ItemJournalLine: Record "Item Journal Line";
        ItemNo: Code[20];
        DocumentNo: Code[20];
        LineNo: Integer;
        ItemIdx: Integer;
        i: Integer;
    begin
        if (LineCount <= 0) or (ItemList.Count() = 0) then
            exit;

        DocumentNo := SelectItemJournalBatch(ItemJournalBatch);
        ItemIdx := 1;

        for i := 1 to LineCount do begin
            LineNo := i * 10000;
            ItemList.Get(ItemIdx, ItemNo);
            CreateIJLine(ItemJournalLine, ItemJournalBatch, ItemNo, LocationCode, LineNo, DocumentNo, WithSN, i);
            ItemIdx += 1;
            if ItemIdx > ItemList.Count() then
                ItemIdx := 1;
        end;

        Commit();
        PostItemJournalBatch(ItemJournalBatch);
        Commit();
    end;

    local procedure CreateIJLine(var ItemJournalLine: Record "Item Journal Line"; ItemJournalBatch: Record "Item Journal Batch"; ItemNo: Code[20]; LocationCode: Code[10]; LineNo: Integer; DocumentNo: Code[20]; WithSN: Boolean; SeqNo: Integer)
    begin
        Clear(ItemJournalLine);
        ItemJournalLine.Init();
        ItemJournalLine.Validate("Journal Template Name", ItemJournalBatch."Journal Template Name");
        ItemJournalLine.Validate("Journal Batch Name", ItemJournalBatch.Name);
        ItemJournalLine.Validate("Line No.", LineNo);
        ItemJournalLine.Validate("Posting Date", WorkDate());
        ItemJournalLine.Validate("Entry Type", ItemJournalLine."Entry Type"::"Positive Adjmt.");
        ItemJournalLine.Validate("Document No.", DocumentNo);
        ItemJournalLine.Insert(true);
        ItemJournalLine.Validate("Item No.", ItemNo);
        if LocationCode <> '' then
            ItemJournalLine.Validate("Location Code", LocationCode);
        // Quantity 1 for S/N items (one serial per line); 10000 for others to ensure enough stock for sales
        if WithSN then
            ItemJournalLine.Validate(Quantity, 1)
        else
            ItemJournalLine.Validate(Quantity, 100000);
        ItemJournalLine.Modify(true);

        if WithSN then
            AssignSerialNo(ItemJournalLine, 'SN-' + Format(SeqNo, 0, '<Integer,10><Filler,0>'));
    end;

    local procedure AssignSerialNo(var ItemJournalLine: Record "Item Journal Line"; SerialNo: Code[50])
    var
        ReservEntry: Record "Reservation Entry";
    begin
        ReservEntry.Init();
        ReservEntry."Entry No." := ReservEntry.GetLastEntryNo() + 1;
        ReservEntry."Item No." := ItemJournalLine."Item No.";
        ReservEntry."Location Code" := ItemJournalLine."Location Code";
        ReservEntry."Quantity (Base)" := 1;
        ReservEntry."Qty. to Handle (Base)" := 1;
        ReservEntry."Qty. to Invoice (Base)" := 1;
        ReservEntry.Positive := true;
        ReservEntry."Reservation Status" := ReservEntry."Reservation Status"::Surplus;
        ReservEntry."Serial No." := SerialNo;
        ReservEntry."Source Type" := Database::"Item Journal Line";
        ReservEntry."Source Subtype" := ItemJournalLine."Entry Type".AsInteger();
        ReservEntry."Source ID" := ItemJournalLine."Journal Template Name";
        ReservEntry."Source Batch Name" := ItemJournalLine."Journal Batch Name";
        ReservEntry."Source Ref. No." := ItemJournalLine."Line No.";
        ReservEntry."Creation Date" := Today();
        ReservEntry."Created By" := CopyStr(UserId(), 1, MaxStrLen(ReservEntry."Created By"));
        ReservEntry.Insert();
    end;

    local procedure SelectItemJournalBatch(var ItemJournalBatch: Record "Item Journal Batch"): Code[20]
    var
        ItemJournalTemplate: Record "Item Journal Template";
        BatchName: Code[10];
    begin
        ItemJournalTemplate.SetRange(Type, ItemJournalTemplate.Type::Item);
        ItemJournalTemplate.SetRange(Recurring, false);
        ItemJournalTemplate.SetLoadFields(Name);
        ItemJournalTemplate.FindFirst();

        BatchName := CopyStr(Format(CreateGuid(), 10, 3), 1, 10);

        ItemJournalBatch.Init();
        ItemJournalBatch."Journal Template Name" := ItemJournalTemplate.Name;
        ItemJournalBatch."Template Type" := ItemJournalBatch."Template Type"::Item;
        ItemJournalBatch.SetupNewBatch();
        ItemJournalBatch.Name := BatchName;
        ItemJournalBatch.Description := 'TEST Data Gen Batch';
        ItemJournalBatch."No. Series" := '';  // no series — posting uses Document No. from lines as-is
        ItemJournalBatch.Insert(true);

        exit('TESTIJ0001');
    end;

    local procedure PostItemJournalBatch(ItemJournalBatch: Record "Item Journal Batch")
    var
        ItemJournalLine: Record "Item Journal Line";
    begin
        ItemJournalLine.Init();
        ItemJournalLine."Journal Template Name" := ItemJournalBatch."Journal Template Name";
        ItemJournalLine."Journal Batch Name" := ItemJournalBatch.Name;
        Codeunit.Run(Codeunit::"Item Jnl.-Post Batch", ItemJournalLine);
    end;

    // Step 5: Create and post sales invoices with random items from the generated set
    local procedure CreateAndPostSalesInvoices(ItemList: List of [Code[20]]; InvoiceCount: Integer; LinesPerInvoice: Integer; LocationCode: Code[10])
    var
        Setup: Record "BCPT Data Gen. Setup";
        Customer: Record Customer;
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
        SalesPost: Codeunit "Sales-Post";
        ItemNo: Code[20];
        StartInvoice: Integer;
        ItemIdx: Integer;
        i: Integer;
        j: Integer;
    begin
        if (InvoiceCount <= 0) or (ItemList.Count() = 0) then
            exit;
        if LinesPerInvoice <= 0 then
            LinesPerInvoice := 1;

        Setup.Get('');
        // Resume from where we left off
        StartInvoice := Setup."Sales Invoices Posted" + 1;
        if StartInvoice > InvoiceCount then
            exit;

        Customer.SetRange("No.", '10000', '40000');
        if not Customer.FindFirst() then
            Customer.FindFirst();

        // Advance item index to stay consistent with prior runs
        ItemIdx := ((StartInvoice - 1) * LinesPerInvoice) mod ItemList.Count() + 1;

        for i := StartInvoice to InvoiceCount do begin
            // PERF ISSUE: CalcFields inside a loop causes one extra SQL query per iteration
            Customer.CalcFields("Balance (LCY)");

            SalesHeader.Init();
            SalesHeader."Document Type" := SalesHeader."Document Type"::Invoice;
            SalesHeader.Insert(true);
            SalesHeader.Validate("Sell-to Customer No.", Customer."No.");
            SalesHeader.Modify(true);

            for j := 1 to LinesPerInvoice do begin
                ItemList.Get(ItemIdx, ItemNo);

                SalesLine.Init();
                SalesLine."Document Type" := SalesHeader."Document Type";
                SalesLine."Document No." := SalesHeader."No.";
                SalesLine."Line No." := j * 10000;
                SalesLine.Insert(true);
                SalesLine.Validate(Type, SalesLine.Type::Item);
                SalesLine.Validate("No.", ItemNo);
                if LocationCode <> '' then
                    SalesLine.Validate("Location Code", LocationCode);
                SalesLine.Validate(Quantity, 1);
                SalesLine.Validate("Tax Group Code", GetTaxGroupCode());
                SalesLine.Modify(true);

                ItemIdx += 1;
                if ItemIdx > ItemList.Count() then
                    ItemIdx := 1;
            end;

            SalesHeader.Validate(Invoice, true);
            SalesPost.Run(SalesHeader);

            if Customer.Next() = 0 then begin
                Customer.SetRange("No.", '10000', '40000');
                Customer.FindFirst();
            end;

            if i mod 10 = 0 then
                SaveSalesProgress(i);
        end;

        SaveSalesProgress(InvoiceCount);
    end;

    local procedure GetTaxGroupCode(): Code[20]
    var
        TaxGroup: Record "Tax Group";
    begin
        if TaxGroup.FindFirst() then
            exit(TaxGroup.Code);
    end;

    local procedure GetGenProdPostingGroup(): Code[20]
    var
        GeneralPostingSetup: Record "General Posting Setup";
    begin
        GeneralPostingSetup.SetFilter("Gen. Prod. Posting Group", '<>%1', '');
        GeneralPostingSetup.SetFilter("Sales Account", '<>%1', '');
        GeneralPostingSetup.SetFilter("COGS Account", '<>%1', '');
        GeneralPostingSetup.SetFilter("Inventory Adjmt. Account", '<>%1', '');
        if GeneralPostingSetup.FindFirst() then
            exit(GeneralPostingSetup."Gen. Prod. Posting Group");
    end;

    local procedure GetInventoryPostingGroup(): Code[20]
    var
        InventoryPostingSetup: Record "Inventory Posting Setup";
    begin
        InventoryPostingSetup.SetFilter("Inventory Account", '<>%1', '');
        InventoryPostingSetup.SetFilter("Location Code", '%1', '');
        if InventoryPostingSetup.FindFirst() then
            exit(InventoryPostingSetup."Invt. Posting Group Code");
    end;

    local procedure GetVATProdPostingGroup(): Code[20]
    var
        VATPostingSetup: Record "VAT Posting Setup";
    begin
        VATPostingSetup.SetFilter("VAT Prod. Posting Group", '<>%1', '');
        VATPostingSetup.SetFilter("VAT %", '<>%1', 0);
        VATPostingSetup.SetRange("VAT Calculation Type", VATPostingSetup."VAT Calculation Type"::"Normal VAT");
        if VATPostingSetup.FindFirst() then
            exit(VATPostingSetup."VAT Prod. Posting Group");
    end;
}
