# find the squares attacking a given square
function squareAttackers(board::Board, sqr::Int)
    enemies = getTheirPieces(board)
    occupied = getOccupied(board)
    return (pawnLeftCaptures(getBitboard(sqr), occupied | ~occupied, board.turn) & getTheirPawns(board)) |
    (pawnRightCaptures(getBitboard(sqr), occupied | ~occupied, board.turn) & getTheirPawns(board)) |
    (KNIGHT_MOVES[sqr] & enemies & getKnights(board)) |
    (bishopMoves(sqr, occupied) & enemies & (getBishops(board) | getQueens(board))) |
    (rookMoves(sqr, occupied) & enemies & (getRooks(board) | getQueens(board))) |
    (KING_MOVES[sqr] & enemies & getKings(board))
end
squareAttackers(board::Board, sqr_bb::UInt) = squareAttackers(board, getSquare(sqr_bb))

# is a given square attacked? Bool.
isSquareAttacked(board::Board, sqr::Int) = squareAttackers(board, square) > zero(UInt)

# find the squares attacking the king!
function checkers(board::Board)
    squareAttackers(board, getOurKing(board))
end

# is the king attacked? Bool.
isCheck(board::Board) = board.checkers > zero(UInt)#squareAttackers(board, getOurKing(board)) > zero(UInt)

# function isTheirKingAttacked(board::Board)
#     switchTurn!(board)
#     bool = isOurKingAttacked(board)
#     switchTurn!(board)
#     return bool
# end

# generate a mask for the bits between two squares of a sliding attack
function initBlockerMasks(blockermasks::Array{UInt, 2})
    for sqr1 in 1:64
        for sqr2 in 1:64
            if (rookMoves(sqr1, zero(UInt)) & getBitboard(sqr2)) > zero(UInt)
                blockermasks[sqr1, sqr2] = rookMoves(sqr1, getBitboard(sqr2)) & rookMoves(sqr2, getBitboard(sqr1))
            end
            if (bishopMoves(sqr1, zero(UInt)) & getBitboard(sqr2)) > zero(UInt)
                blockermasks[sqr1, sqr2] = bishopMoves(sqr1, getBitboard(sqr2)) & bishopMoves(sqr2, getBitboard(sqr1))
            end
        end
    end
    return blockermasks
end

# pre compute blocker masks.
const BLOCKERMASKS = initBlockerMasks(zeros(UInt, (64,64)))
