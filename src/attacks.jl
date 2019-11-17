# find the squares attacking a given square
function squareAttackers(board::Board, sqr::Int)
    enemies = (board.turn == WHITE) ? getBlack(board) : getWhite(board)
    occupied = getOccupied(board)
    return (pawnLeftCaptures(getBitboard(sqr), occupied | ~occupied, board.turn) & getTheirPawns(board)) |
    (pawnRightCaptures(getBitboard(sqr), occupied | ~occupied, board.turn) & getTheirPawns(board)) |
    (KNIGHT_MOVES[sqr] & enemies & board.knights) |
    (bishopMoves(sqr, occupied) & enemies & (board.bishops | board.queens)) |
    (rookMoves(sqr, occupied) & enemies & (board.rooks | board.queens)) |
    (KING_MOVES[sqr] & enemies & board.kings)
end
squareAttackers(board::Board, sqr::UInt) = squareAttackers(board, getSquare(sqr))

# is a given square attacked? Bool.
isSquareAttacked(board::Board, sqr::Int) = squareAttackers(board, square) > zero(UInt)

# find the squares attacking the king!
function kingAttackers(board::Board)
    squareAttackers(board, getOurKing(board))
end

# is the king attacked? Bool.
isKingAttacked(board::Board) = squareAttackers(board, getOurKing(board)) > zero(UInt)

# generate a mask for the bits between two squares of a sliding attack
function initBlockerMasks(blockermasks::Array{UInt, 2})
    for sqr1 in 1:64
        for sqr2 in 1:64
            if (rookMoves(sqr1, zero(UInt)) & getBitboard(sqr2)) > zero(UInt)
                blockermasks[sqr1, sqr2] = rookMoves(sqr1, zero(UInt)) & rookMoves(sqr2, zero(UInt))
            end
            if (bishopMoves(sqr1, zero(UInt)) & getBitboard(sqr2)) > zero(UInt)
                blockermasks[sqr1, sqr2] = bishopMoves(sqr1, zero(UInt)) & bishopMoves(sqr2, zero(UInt))
            end
        end
    end
    return blockermasks
end

# pre compute blocker masks.
const BLOCKERMASKS = initBlockerMasks(zeros(UInt, (64,64)))