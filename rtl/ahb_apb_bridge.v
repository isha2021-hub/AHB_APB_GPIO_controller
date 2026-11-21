

module ahb_apb_bridge (
    // AHB-Lite interface
    input  wire        HCLK,
    input  wire        HRESETn,
    input  wire        HSEL,
    input  wire [31:0] HADDR,
    input  wire        HWRITE,
    input  wire [1:0]  HTRANS,
    input  wire [31:0] HWDATA,
    input  wire        HREADY,

    output reg  [31:0] HRDATA,
    output reg         HREADYOUT,
    output reg         HRESP,

    // APB3 interface
    output reg  [31:0] PADDR,
    output reg         PSEL,
    output reg         PENABLE,
    output reg         PWRITE,
    output reg  [31:0] PWDATA,

    input  wire [31:0] PRDATA,
    input  wire        PREADY,
    input  wire        PSLVERR
);

    localparam IDLE       = 3'b000;
    localparam WRITE_DATA = 3'b001;
    localparam SETUP      = 3'b010;
    localparam ACCESS     = 3'b011;
    localparam ERROR_1    = 3'b100;
    localparam ERROR_2    = 3'b101;

    reg [2:0] state;

    // Capture AHB address and control information
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            state  <= IDLE;
            PADDR  <= 32'b0;
            PWRITE <= 1'b0;
            PWDATA <= 32'b0;
        end
        else begin
            case (state)

                IDLE: begin
                    // HTRANS[1] = 1 for NONSEQ or SEQ
                    if (HSEL && HTRANS[1] && HREADY) begin
                        PADDR  <= HADDR;
                        PWRITE <= HWRITE;

                        if (HWRITE)
                            state <= WRITE_DATA;
                        else
                            state <= SETUP;
                    end
                end

                WRITE_DATA: begin
                    // AHB write data arrives in the next phase
                    PWDATA <= HWDATA;
                    state  <= SETUP;
                end

                SETUP: begin
                    state <= ACCESS;
                end

                ACCESS: begin
                    // Remain in ACCESS until APB peripheral is ready
                    if (PREADY) begin
                        if (PSLVERR)
                            state <= ERROR_1;
                        else
                            state <= IDLE;
                    end
                end

                ERROR_1: state <= ERROR_2;

                ERROR_2: state <= IDLE;

                default: state <= IDLE;
            endcase
        end
    end

    // AHB and APB output control
    always @(*) begin
        PSEL      = 1'b0;
        PENABLE   = 1'b0;

        HRDATA    = 32'b0;
        HREADYOUT = 1'b0;
        HRESP     = 1'b0;

        case (state)

            IDLE: begin
                HREADYOUT = 1'b1;
            end

            WRITE_DATA: begin
                HREADYOUT = 1'b0;
            end

            SETUP: begin
                PSEL    = 1'b1;
                PENABLE = 1'b0;
            end

            ACCESS: begin
                PSEL    = 1'b1;
                PENABLE = 1'b1;

                if (PREADY) begin
                    if (PSLVERR) begin
                        HREADYOUT = 1'b0;
                    end
                    else begin
                        HREADYOUT = 1'b1;

                        // Return peripheral data for AHB reads
                        if (!PWRITE)
                            HRDATA = PRDATA;
                    end
                end
            end

            ERROR_1: begin
                HRESP     = 1'b1;
                HREADYOUT = 1'b0;
            end

            ERROR_2: begin
                HRESP     = 1'b1;
                HREADYOUT = 1'b1;
            end

            default: begin
                HREADYOUT = 1'b1;
            end

        endcase
    end

endmodule


