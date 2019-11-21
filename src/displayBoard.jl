# Function to display the board, using colors and standard chess symbols.
# 9 x 9 board, where the first column, and last row are used to annotate the coords.
function displayColorBoard(board::Board)
    for row in 1:9
        for col in 1:9
            if row == 9
                (col > 1) ? print(COLUMNS[col - 1]*" ") : print("  ")
            elseif col == 1
                print(9 - row, " ")
            else
                sqr = getSquare(col - 1, 9 - row)
                color = getPieceColor(board, sqr)
                piece = getPieceType(board, sqr)
                sym = (piece > zero(UInt8)) ? SYMBOLS[getPieceType(board, sqr)] : ' '
                foreground = (color == WHITE) ? :white : :black
                background = isodd(row + col + 1) ? :blue : :light_blue
                print(Crayon(foreground = foreground, background = background), sym, " ")
                if (row == 1) && (col == 9) && (board.turn == WHITE)
                    print(Crayon(reset = true), " White to move...")
                elseif (row == 1) && (col == 9) && (board.turn == BLACK)
                    print(Crayon(reset = true), " Black to move...")
                end
            end
        end
        print(Crayon(reset = true), "\n")
    end
end

# useful for visualising the bitboard masks, attacks, pieces etc. (testing and debugging)
function displayBitboard(bitboard::UInt64)
    for row in 1:9
        for col in 1:9
            if row == 9
                (col > 1) ? print(COLUMNS[col - 1]*" ") : print("  ")
            elseif col == 1
                print(9 - row, " ")
            else
                sqr = getBitboard(col - 1, 9 - row)
                sym = ((sqr & bitboard) > zero(UInt)) ? 'x' : ' '
                foreground = :red
                background = isodd(row + col + 1) ? :blue : :light_blue
                print(Crayon(foreground = foreground, background = background), sym, " ")
            end
        end
        print(Crayon(reset = true), "\n")
    end
end
