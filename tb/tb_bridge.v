
`timescale 1ns/1ps

module tb_bridge;

    reg HCLK, HRESETn;
    reg HSEL, HWRITE, HREADY;
    reg [31:0] HADDR, HWDATA;
    reg [1:0] HTRANS;

    wire [31:0] HRDATA;
    wire HREADYOUT, HRESP;

    wire [31:0] PADDR, PWDATA;
    wire PSEL, PENABLE, PWRITE;

    reg [31:0] PRDATA;
    reg PREADY, PSLVERR;

    // Instantiate bridge
    ahb_apb_bridge dut (
        .HCLK(HCLK),
        .HRESETn(HRESETn),
        .HSEL(HSEL),
        .HADDR(HADDR),
        .HWRITE(HWRITE),
        .HTRANS(HTRANS),
        .HWDATA(HWDATA),
        .HREADY(HREADY),

        .HRDATA(HRDATA),
        .HREADYOUT(HREADYOUT),
        .HRESP(HRESP),

        .PADDR(PADDR),
        .PSEL(PSEL),
        .PENABLE(PENABLE),
        .PWRITE(PWRITE),
        .PWDATA(PWDATA),

        .PRDATA(PRDATA),
        .PREADY(PREADY),
        .PSLVERR(PSLVERR)
    );

    // Clock generation: 10 ns period
    always #5 HCLK = ~HCLK;

    // AHB write transaction
    task ahb_write;
        input [31:0] address;
        input [31:0] data;
        integer i;
        begin
            @(negedge HCLK);
            HSEL = 1;
            HTRANS = 2'b10;
            HWRITE = 1;
            HADDR = address;

            @(posedge HCLK);
            #1;
            @(negedge HCLK);
            HSEL = 0;
            HTRANS = 2'b00;
            HWDATA = data;

            @(posedge HCLK);
            #1;

            // Check APB setup phase
            if (PSEL !== 1 || PENABLE !== 0)
                $fatal(1, "FAIL: Write APB setup");

            if (PADDR !== address || PWRITE !== 1)
                $fatal(1, "FAIL: Write address/control");

            if (PWDATA !== data)
                $fatal(1, "FAIL: Write data");

            @(posedge HCLK);
            #1;

            // Check APB access phase
            if (PSEL !== 1 || PENABLE !== 1)
                $fatal(1, "FAIL: Write APB access");

            // Insert two wait cycles
            for (i = 0; i < 2; i = i + 1) begin
                @(negedge HCLK);
                if (PSEL !== 1 || PENABLE !== 1)
                    $fatal(1, "FAIL: APB signals not held during wait");
                if (HREADYOUT !== 0)
                    $fatal(1, "FAIL: HREADYOUT during wait");
                @(posedge HCLK);
                #1;
            end

           @(negedge HCLK);
            PREADY = 1;
            #1;  // Allow combinational outputs to update

            if (HREADYOUT !== 1)
                 $fatal(1, "FAIL: Write completion");

            @(posedge HCLK);
            #1;
            PREADY = 0;

            $display("PASS: AHB WRITE");
        end
    endtask

    // AHB read transaction
    task ahb_read;
        input [31:0] address;
        input [31:0] expected_data;
        begin
            @(negedge HCLK);
            HSEL = 1;
            HTRANS = 2'b10;
            HWRITE = 0;
            HADDR = address;

            @(posedge HCLK);
            #1;
            @(negedge HCLK);
            HSEL = 0;
            HTRANS = 2'b00;

            // APB setup
            #1;
            if (PSEL !== 1 || PENABLE !== 0)
                $fatal(1, "FAIL: Read APB setup");

            @(posedge HCLK);
            #1;

            // APB access
            if (PSEL !== 1 || PENABLE !== 1)
                $fatal(1, "FAIL: Read APB access");

            @(negedge HCLK);
            PRDATA = expected_data;
            PREADY = 1;

            // Check read data before completion edge
            #1;
            if (HRDATA !== expected_data)
                $fatal(1, "FAIL: Incorrect read data");

            if (HREADYOUT !== 1)
                $fatal(1, "FAIL: Read completion");

            @(posedge HCLK);
            #1;
            PREADY = 0;

            $display("PASS: AHB READ");
        end
    endtask

    // APB error response test
    task ahb_error_test;
        begin
            @(negedge HCLK);
            HSEL = 1;
            HTRANS = 2'b10;
            HWRITE = 0;
            HADDR = 32'h00000008;

            @(posedge HCLK);
            #1;
            @(negedge HCLK);
            HSEL = 0;
            HTRANS = 2'b00;

            @(posedge HCLK);
            #1;

            @(negedge HCLK);
            PREADY = 1;
            PSLVERR = 1;

            @(posedge HCLK);
            #1;

            // First ERROR cycle
            if (HRESP !== 1 || HREADYOUT !== 0)
                $fatal(1, "FAIL: First ERROR cycle");

            @(posedge HCLK);
            #1;

            // Second ERROR cycle
            if (HRESP !== 1 || HREADYOUT !== 1)
                $fatal(1, "FAIL: Second ERROR cycle");

            @(posedge HCLK);
            #1;

            PREADY = 0;
            PSLVERR = 0;

            if (HRESP !== 0)
                $fatal(1, "FAIL: Error response did not clear");

            $display("PASS: TWO-CYCLE AHB ERROR");
        end
    endtask

    // Main test sequence
    initial begin
        HCLK = 0;
        HRESETn = 0;

        HSEL = 0;
        HWRITE = 0;
        HREADY = 1;
        HADDR = 0;
        HWDATA = 0;
        HTRANS = 0;

        PRDATA = 0;
        PREADY = 0;
        PSLVERR = 0;

        // Reset
        repeat (3) @(posedge HCLK);
        @(negedge HCLK);
        HRESETn = 1;

        // Test 1: AHB write with APB wait states
        ahb_write(32'h00000004, 32'h00000005);

        // Test 2: AHB read
        ahb_read(32'h00000008, 32'h000000A5);

        // Test 3: Peripheral error response
        ahb_error_test();

        $display("--------------------------------");
        $display("ALL BRIDGE TESTS COMPLETED");
        $display("--------------------------------");

        $finish;
    end

endmodule
