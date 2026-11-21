
`timescale 1ns/1ps

module tb_gpio;

    parameter integer WAIT_CYCLES = 0;

    reg PCLK;
    reg PRESETn;

    reg [31:0] PADDR;
    reg PSEL;
    reg PENABLE;
    reg PWRITE;
    reg [31:0] PWDATA;

    wire [31:0] PRDATA;
    wire PREADY;
    wire PSLVERR;

    reg [7:0] gpio_in;
    wire [7:0] gpio_out;
    wire [7:0] gpio_oe;

    integer errors = 0;
    integer wait_count = 0;

    // Instantiate GPIO peripheral
    gpio_peripheral #(
        .WAIT_CYCLES(WAIT_CYCLES)
    ) DUT (
        .PCLK(PCLK),
        .PRESETn(PRESETn),

        .PADDR(PADDR),
        .PSEL(PSEL),
        .PENABLE(PENABLE),
        .PWRITE(PWRITE),
        .PWDATA(PWDATA),

        .PRDATA(PRDATA),
        .PREADY(PREADY),
        .PSLVERR(PSLVERR),

        .gpio_in(gpio_in),
        .gpio_out(gpio_out),
        .gpio_oe(gpio_oe)
    );

    // Clock generation: 10 ns period
    initial begin
        PCLK = 0;
        forever #5 PCLK = ~PCLK;
    end

    // APB write task
    task apb_write;
        input [31:0] address;
        input [31:0] data;

        begin
            @(negedge PCLK);
            PADDR   = address;
            PWDATA  = data;
            PWRITE  = 1;
            PSEL    = 1;
            PENABLE = 0;

            @(negedge PCLK);
            PENABLE = 1;

            wait_count = 0;

            while (PREADY !== 1'b1) begin
                @(negedge PCLK);
                wait_count = wait_count + 1;
            end

            @(posedge PCLK);
            #1;

            if (PSLVERR)
                $display("WRITE ERROR at address %h", address);

            @(negedge PCLK);
            PSEL    = 0;
            PENABLE = 0;
            PWRITE  = 0;

            $display("WRITE: ADDR=%h DATA=%h WAIT=%0d",
                     address, data, wait_count);
        end
    endtask

    // APB read task
    task apb_read;
        input [31:0] address;
        input [31:0] expected;

        begin
            @(negedge PCLK);
            PADDR   = address;
            PWRITE  = 0;
            PSEL    = 1;
            PENABLE = 0;

            @(negedge PCLK);
            PENABLE = 1;

            wait_count = 0;

            while (PREADY !== 1'b1) begin
                @(negedge PCLK);
                wait_count = wait_count + 1;
            end

            #1;

            if (PRDATA !== expected) begin
                $display("FAIL: ADDR=%h EXPECTED=%h ACTUAL=%h",
                         address, expected, PRDATA);
                errors = errors + 1;
            end
            else begin
                $display("PASS: ADDR=%h DATA=%h",
                         address, PRDATA);
            end

            @(posedge PCLK);
            @(negedge PCLK);

            PSEL    = 0;
            PENABLE = 0;

        end
    endtask

    // Main test sequence
    initial begin

        $dumpfile("sim/gpio.vcd");
        $dumpvars(0, tb_gpio);

        // Initialize signals
        PRESETn = 0;
        PADDR = 0;
        PWDATA = 0;
        PSEL = 0;
        PENABLE = 0;
        PWRITE = 0;
        gpio_in = 8'h00;

        // Apply reset
        repeat (3) @(negedge PCLK);
        PRESETn = 1;

        // Test 1: Reset values
        apb_read(32'h00, 32'h00000000);
        apb_read(32'h04, 32'h00000000);

        // Test 2: Configure GPIO direction
        apb_write(32'h00, 32'h0000000F);

        // Test 3: Write output register
        apb_write(32'h04, 32'h00000005);

        // Check GPIO output and enable
        #1;
        if (gpio_out !== 8'h05 || gpio_oe !== 8'h0F) begin
            $display("FAIL: GPIO output or enable mismatch");
            errors = errors + 1;
        end
        else
            $display("PASS: GPIO output = %h, enable = %h",
                     gpio_out, gpio_oe);

        // Test 4: Read DIR and OUT
        apb_read(32'h00, 32'h0000000F);
        apb_read(32'h04, 32'h00000005);

        // Test 5: Read external input pins
        gpio_in = 8'hA5;
        apb_read(32'h08, 32'h000000A5);

        // Test 6: SET register
        apb_write(32'h0C, 32'h00000002);
        apb_read(32'h04, 32'h00000007);

        // Test 7: CLEAR register
        apb_write(32'h10, 32'h00000001);
        apb_read(32'h04, 32'h00000006);

        // Test 8: TOGGLE register
        apb_write(32'h14, 32'h00000003);
        apb_read(32'h04, 32'h00000005);

        // Test 9: Upper read bits must be zero
        apb_read(32'h04, 32'h00000005);

        // Final result
        if (errors == 0)
            $display("\nALL GPIO TESTS PASSED");
        else
            $display("\nGPIO TESTS FAILED: %0d errors", errors);

        $finish;
    end

endmodule
