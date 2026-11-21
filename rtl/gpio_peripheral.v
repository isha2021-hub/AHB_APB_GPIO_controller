
module gpio_peripheral #(
    parameter integer WAIT_CYCLES = 0
)(
    input  wire        PCLK,
    input  wire        PRESETn,

    // APB3 interface
    input  wire [31:0] PADDR,
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [31:0] PWDATA,

    output reg  [31:0] PRDATA,
    output wire        PREADY,
    output wire        PSLVERR,

    // External GPIO interface
    input  wire [7:0]  gpio_in,
    output wire [7:0]  gpio_out,
    output wire [7:0]  gpio_oe
);

    // GPIO register addresses
    localparam [31:0] DIR_ADDR    = 32'h00;
    localparam [31:0] OUT_ADDR    = 32'h04;
    localparam [31:0] IN_ADDR     = 32'h08;
    localparam [31:0] SET_ADDR    = 32'h0C;
    localparam [31:0] CLEAR_ADDR  = 32'h10;
    localparam [31:0] TOGGLE_ADDR = 32'h14;

    // Internal registers
    reg [7:0] dir_reg;
    reg [7:0] out_reg;

    // APB wait-state counter
    integer wait_count;

    wire apb_access;
    wire valid_address;

    assign apb_access = PSEL && PENABLE;

    assign valid_address =
        (PADDR == DIR_ADDR)    ||
        (PADDR == OUT_ADDR)    ||
        (PADDR == IN_ADDR)     ||
        (PADDR == SET_ADDR)    ||
        (PADDR == CLEAR_ADDR)  ||
        (PADDR == TOGGLE_ADDR);

    // APB ready signal
    assign PREADY = apb_access &&
                    (wait_count >= WAIT_CYCLES);

    // Error for unsupported register addresses
    assign PSLVERR = apb_access &&
                     PREADY &&
                     !valid_address;

    // GPIO output and output-enable signals
    assign gpio_out = out_reg & dir_reg;
    assign gpio_oe  = dir_reg;

    // APB read operation
    always @(*) begin
        PRDATA = 32'h00000000;

        if (PSEL && !PWRITE) begin
            case (PADDR)
                DIR_ADDR:
                    PRDATA = {24'b0, dir_reg};

                OUT_ADDR:
                    PRDATA = {24'b0, out_reg};

                IN_ADDR:
                    PRDATA = {24'b0, gpio_in};

                default:
                    PRDATA = 32'h00000000;
            endcase
        end
    end

    // Wait-state generation
    always @(posedge PCLK) begin
        if (!PRESETn) begin
            wait_count <= 0;
        end
        else if (!apb_access) begin
            wait_count <= 0;
        end
        else if (wait_count < WAIT_CYCLES) begin
            wait_count <= wait_count + 1;
        end
    end

    // GPIO register write operations
    always @(posedge PCLK) begin
        if (!PRESETn) begin
            dir_reg <= 8'h00;
            out_reg <= 8'h00;
        end
        else if (apb_access && PREADY && PWRITE && !PSLVERR) begin

            case (PADDR)

                DIR_ADDR:
                    dir_reg <= PWDATA[7:0];

                OUT_ADDR:
                    out_reg <= PWDATA[7:0];

                SET_ADDR:
                    out_reg <= out_reg | PWDATA[7:0];

                CLEAR_ADDR:
                    out_reg <= out_reg & ~PWDATA[7:0];

                TOGGLE_ADDR:
                    out_reg <= out_reg ^ PWDATA[7:0];

                default: begin
                    dir_reg <= dir_reg;
                    out_reg <= out_reg;
                end

            endcase
        end
    end

endmodule
