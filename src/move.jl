# https://www.chessprogramming.org/Encoding_Moves
# Idea is to use a 16-bit Int to encode the move.
# 6 bits for "from", 6 bits for "to", 4 bits for "flags"
const FLAGS = [:__NORMAL_MOVE, :__DOUBLE_PAWN, :__KING_CASTLE, :__QUEEN_CASTLE, :__ENPASS,
    :__KNIGHT_PROMO, :__BISHOP_PROMO, :__ROOK_PROMO, :__QUEEN_PROMO]

for (num, flag) in enumerate(FLAGS)
    @eval const $flag = UInt16($num - 1) << 12
end


"""
    updatecastling!(board::Board, sqr_from::Integer, sqr_to::Integer)

Update the castling rights of the `board`, given a move is played from `sqr_from` to `sqr_to`.
"""
function updatecastling!(board::Board, sqr_from::Integer, sqr_to::Integer)
    board.hash ⊻= zobookey(board.castling)
    @inbounds board.castling &= CASTLING_RIGHT[sqr_from]
    @inbounds board.castling &= CASTLING_RIGHT[sqr_to]
    board.hash ⊻= zobookey(board.castling)
end


# Used for internally changing the castling rights when a move is played.
const CASTLING_RIGHT = @SVector [~0x01, ~0x00, ~0x00, ~0x05, ~0x00, ~0x00, ~0x00, ~0x04,
                                ~0x00, ~0x00, ~0x00, ~0x00, ~0x00, ~0x00, ~0x00, ~0x00,
                                ~0x00, ~0x00, ~0x00, ~0x00, ~0x00, ~0x00, ~0x00, ~0x00,
                                ~0x00, ~0x00, ~0x00, ~0x00, ~0x00, ~0x00, ~0x00, ~0x00,
                                ~0x00, ~0x00, ~0x00, ~0x00, ~0x00, ~0x00, ~0x00, ~0x00,
                                ~0x00, ~0x00, ~0x00, ~0x00, ~0x00, ~0x00, ~0x00, ~0x00,
                                ~0x00, ~0x00, ~0x00, ~0x00, ~0x00, ~0x00, ~0x00, ~0x00,
                                ~0x02, ~0x00, ~0x00, ~0x0a, ~0x00, ~0x00, ~0x00, ~0x08]


Move() = Move(zero(UInt16))

const MOVE_NONE = Move()
const NULL_MOVE = Move(0xffff)


"""
    Move(move_from::Integer, move_to::Integer, move_flag::Integer)

Encode a move, giving the from & to squares, alongside the move flag.
"""
function Move(move_from::Integer, move_to::Integer, move_flag::Integer)
    Move((move_from - one(move_from)) | ((move_to - one(move_from)) << 6) | move_flag)
end


"""
    Move(move_from::Integer, move_to::Integer, move_flag::Integer)

Encode a move, giving the from & to squares, assuming no move flags.
"""
function Move(move_from::Integer, move_to::Integer)
    Move((move_from - one(move_from)) | ((move_to - one(move_from)) << 6))
end
# the above function saves one bitwise 'or' operation per normal move generation.
# Move(move_from::Integer, move_to::Integer) = Move(move_from, move_to, __NORMAL_MOVE)


"""
    from(move::Move)

Given a move, retrieve the "move from" square, as an `Integer`.
"""
from(move::Move) = (move.val & 0x003f) + 0x0001


"""
    to(move::Move)

Given a move, retrieve the "move to" square, as an `Integer`.
"""
to(move::Move) = ((move.val >> 6) & 0x003f) + 0x0001


"""
    flag(move::Move)

Given a move, return any special flags, as an `Integer`.
"""
flag(move::Move) = move.val & 0xf000 #>> 12


"""
    istactical (board::Board, move::Move)

Given the board position and a move, return true if a move is tactical.
A tactical move involves a capture, promotion, or castling.
"""
function istactical(board::Board, move::Move)
    if flag(move) > __DOUBLE_PAWN
        # All flag values above __DOUBLE_PAWN are tactical.
        return true
    elseif board[to(move)] !== BLANK
        # Capture case
        return true
    else
        return false
    end
end


# Allows a preallocation for MoveStack
# MoveStack(size::Int) = MoveStack(Vector{Move}(undef, size), 0)
MoveStack(size::Int) = MoveStack(repeat([MOVE_NONE], size), 0)


# define useful array methods for MoveStack
Base.iterate(m::MoveStack, state = 1) = (state > m.idx) ? nothing : (m.list[state], state + 1)
Base.length(m::MoveStack) = m.idx
Base.eltype(::Type{MoveStack}) = Move
Base.size(m::MoveStack) = (m.idx, )
Base.IndexStyle(::Type{<:MoveStack}) = IndexLinear()
Base.getindex(m::MoveStack, idx::Int) = m.list[idx]
Base.setindex!(m::MoveStack, val::Move, idx::Int) = @inbounds m.list[idx] = val


# add moves to the MoveStack
function push!(m::MoveStack, move::Move)
    m.idx += 1
    @inbounds m.list[m.idx] = move
end


# pseudo-clear the MoveStack
clear!(m::MoveStack) = m.idx = 0


# Allows a preallocation for MoveStack
UndoStack(size::Int) = UndoStack(Vector{Undo}(undef, size), 0)


# define useful array methods for UndoStack
Base.iterate(u::UndoStack, state = 1) = (state > u.idx) ? nothing : (u.list[state], state + 1)
Base.length(u::UndoStack) = u.idx
Base.eltype(::Type{UndoStack}) = Undo
Base.size(u::UndoStack) = (u.idx, )
Base.IndexStyle(::Type{<:UndoStack}) = IndexLinear()
Base.getindex(u::UndoStack, idx::Int) = u.list[idx]


# add Undos to the UndoStack
function push!(u::UndoStack, undo::Undo)
    u.idx += 1
    @inbounds u.list[u.idx] = undo
end


# pseudo-clear the UndoStack
clear!(u::UndoStack) = u.idx = 0


"""
    apply_move!(board::Board, move::Move, undo::Undo)

Apply the given `move` to the `board`, adding changes to 'undo'.
"""
function apply_move!(board::Board, move::Move)
    undo_checkers = board.checkers
    undo_pinned = board.pinned
    undo_castling = board.castling
    undo_enpass = board.enpass
    undo_halfmovecount = board.halfmovecount
    undo_hash = board.hash
    undo_psqteval = board.psqteval
    undo_pkhash = board.pkhash

    # before we update the enpass
    if board.enpass !== zero(UInt8)
        board.hash ⊻= zobepkey(board.enpass)
    end

    # Apply the moves according to the appropriate flag
    if flag(move) <= __DOUBLE_PAWN
        # If the move is normal or a double pawn push
        undo_captured = apply_normal!(board, move)
    elseif flag(move) === __ENPASS
        # If the move is enpassant
        undo_captured = apply_enpass!(board, move)
    elseif flag(move) <= __QUEEN_CASTLE
        # If the move is castling fallthrough.
        undo_captured = apply_castle!(board, move)
    else
        # Otherwise it's a promotion fallthrough.
        undo_captured = apply_promo!(board, move)
    end

    # Finishing calculations, for the next turn
    board.hash ⊻= zobturnkey()
    switchturn!(board)

    board.checkers = kingAttackers(board)
    board.pinned = findpins(board)
    board.movecount += one(board.movecount)
    @inbounds board.history[board.movecount] = board.hash
    return Undo(undo_checkers, undo_pinned, undo_castling, undo_enpass, undo_captured, undo_halfmovecount, undo_hash, undo_psqteval, undo_pkhash)
end


# This function is the same as above
# ... but includes the option to update the thread movestack and piecestack for history heuristics.
function apply_move!(thread::Thread, move::Move)
    board = thread.board
    push!(thread.movestack, move)
    push!(thread.piecestack, type(board[from(move)]))
    u = apply_move!(board, move)
    return u
end


"""
    apply_normal!(board::Board, move::Move)

Apply the given `move` to the `board`. Assumes the move has either the `__NORMAL_MOVE` or `__DOUBLE_PAWN` flags.
"""
function apply_normal!(board::Board, move::Move)
    sqr_from = from(move)
    sqr_to = to(move)

    # Check for double pawn advance and set enpass square
    if flag(move) === __DOUBLE_PAWN
        if board.turn === WHITE
            board.enpass = UInt8(sqr_from + 8)
        else
            board.enpass = UInt8(sqr_from - 8)
        end
        board.hash ⊻= zobepkey(sqr_from)
    else
        board.enpass = zero(UInt8)
    end

    board.castling > 0x00 && updatecastling!(board, sqr_from, sqr_to)

    p_from = piece(board, sqr_from)
    p_to = piece(board, sqr_to)

    bb_from = Bitboard(sqr_from)
    bb_to = Bitboard(sqr_to)

    ptype_from = type(p_from)

    @inbounds board[ptype_from] ⊻= bb_from ⊻ bb_to
    @inbounds board[board.turn] ⊻= bb_from ⊻ bb_to
    @inbounds board[sqr_from] = BLANK
    @inbounds board[sqr_to] = p_from

    # Update PSQT
    board.psqteval -= psqt(p_from, sqr_from)
    board.psqteval += psqt(p_from, sqr_to)

    if p_to !== BLANK
        ptype_to = type(p_to)
        if ptype_to == PAWN
            board.pkhash ⊻= zobkey(p_to, sqr_to)
        end
        @inbounds board[ptype_to] ⊻= bb_to
        @inbounds board[!board.turn] ⊻= bb_to
        board.hash ⊻= zobkey(p_to, sqr_to)

        # Update PSQT
        board.psqteval -= psqt(p_to, sqr_to)
    end

    if (ptype_from === PAWN) || (p_to !== BLANK)
        board.halfmovecount = 0
    else
        board.halfmovecount += 1
    end

    board.hash ⊻= zobkey(p_from, sqr_from)
    board.hash ⊻= zobkey(p_from, sqr_to)

    if ptype_from === PAWN || ptype_from == KING
        board.pkhash ⊻= zobkey(p_from, sqr_from)
        board.pkhash ⊻= zobkey(p_from, sqr_to)
    end

    return p_to
end


"""
    apply_enpass!(board::Board, move::Move)

Apply the given `move` to the `board`. Assumes the move has the `__ENPASS` flag.
"""
function apply_enpass!(board::Board, move::Move)
    board.enpass = zero(UInt8)

    sqr_from = from(move)
    sqr_to = to(move)

    cap_sqr = sqr_to - 24 + (board.turn.val << 4)
    cap_bb = Bitboard(cap_sqr)

    bb_from = Bitboard(sqr_from)
    bb_to = Bitboard(sqr_to)

    @inbounds board[PAWN] ⊻= bb_from ⊻ bb_to ⊻ cap_bb
    @inbounds board[board.turn] ⊻= bb_from ⊻ bb_to
    @inbounds board[!board.turn] ⊻= cap_bb

    # First set the square to
    @inbounds board[sqr_to] = piece(board, sqr_from)
    # Then clear the square from
    @inbounds board[sqr_from] = BLANK
    # Then clear the captured square
    @inbounds board[cap_sqr] = BLANK

    p_from = makepiece(PAWN, board.turn)
    p_capt = makepiece(PAWN, !board.turn)
    board.hash ⊻= zobkey(p_from, sqr_from)
    board.hash ⊻= zobkey(p_from, sqr_to)
    board.hash ⊻= zobkey(p_capt, cap_sqr)

    # Update PSQT
    board.psqteval -= psqt(p_from, sqr_from)
    board.psqteval += psqt(p_from, sqr_to)
    board.psqteval -= psqt(p_capt, cap_sqr)

    board.halfmovecount = 0

    board.pkhash ⊻= zobkey(p_capt, cap_sqr)
    board.pkhash ⊻= zobkey(p_from, sqr_from)
    board.pkhash ⊻= zobkey(p_from, sqr_to)

    return p_capt
end


"""
    apply_castle!(board::Board, move::Move)

Apply the given `move` to the `board`. Assumes the move has the `__KING_CASTLE` or `__QUEEN_CASTLE` flag.
"""
function apply_castle!(board::Board, move::Move)
    board.enpass = zero(UInt8)

    k_from = from(move)
    k_to = to(move)

    updatecastling!(board, k_from, k_to)

    if flag(move) === __KING_CASTLE
        r_from = k_from - 3
        r_to = k_from - 1
    else
        r_from = k_from + 4
        r_to = k_from + 1
    end

    r_from_bb = Bitboard(r_from)
    r_to_bb = Bitboard(r_to)
    k_from_bb = Bitboard(k_from)
    k_to_bb = Bitboard(k_to)

    @inbounds board[KING] ⊻= k_from_bb ⊻ k_to_bb
    @inbounds board[ROOK] ⊻= r_from_bb ⊻ r_to_bb

    @inbounds board[board.turn] ⊻= k_from_bb ⊻ k_to_bb ⊻ r_from_bb ⊻ r_to_bb

    @inbounds board[k_from] = BLANK
    @inbounds board[r_from] = BLANK

    _king = makepiece(KING, board.turn)
    _rook = makepiece(ROOK, board.turn)
    @inbounds board[k_to] = _king
    @inbounds board[r_to] = _rook

    board.hash ⊻= zobkey(_king, k_from)
    board.hash ⊻= zobkey(_king, k_to)
    board.hash ⊻= zobkey(_rook, r_from)
    board.hash ⊻= zobkey(_rook, r_to)

    # Update PSQT
    board.psqteval -= psqt(_king, k_from)
    board.psqteval -= psqt(_rook, r_from)
    board.psqteval += psqt(_king, k_to)
    board.psqteval += psqt(_rook, r_to)

    board.pkhash ⊻= zobkey(_king, k_from)
    board.pkhash ⊻= zobkey(_king, k_to)

    board.halfmovecount += 1

    return BLANK
end


"""
    apply_promo!(board::Board, move::Move)

Apply the given `move` to the `board`. Assumes the move has the `__<PIECE>_PROMO` flag, where `<PIECE>` is either a `KNIGHT`, `BISHOP`, `ROOK`, or `QUEEN`.
"""
function apply_promo!(board::Board, move::Move)
    board.enpass = zero(UInt8)

    sqr_from = from(move)
    sqr_to = to(move)

    board.castling > 0x00 && updatecastling!(board, sqr_from, sqr_to)

    bb_from = Bitboard(sqr_from)
    bb_to = Bitboard(sqr_to)

    p_to = piece(board, sqr_to)
    ptype_promo = PieceType((flag(move)>>12) - 3)

    @inbounds board[PAWN] ⊻= bb_from
    @inbounds board[ptype_promo] ⊻= bb_to
    @inbounds board[board.turn] ⊻= bb_from ⊻ bb_to

    @inbounds board[sqr_from] = BLANK

    p_promo = makepiece(ptype_promo, board.turn)
    @inbounds board[sqr_to] = p_promo

    # Update PSQT
    board.psqteval -= psqt(makepiece(PAWN, board.turn), sqr_from)
    board.psqteval += psqt(p_promo, sqr_to)

    if p_to !== BLANK
        @inbounds board[type(p_to)] ⊻= bb_to
        @inbounds board[!board.turn] ⊻= bb_to
        board.hash ⊻= zobkey(p_to, sqr_to)

        # Update PSQT
        board.psqteval -= psqt(p_to, sqr_to)
    end

    p_from = makepiece(PAWN, board.turn)
    board.hash ⊻= zobkey(p_from, sqr_from)
    board.hash ⊻= zobkey(p_promo, sqr_to)

    board.pkhash ⊻= zobkey(p_from, sqr_from)

    board.halfmovecount = 0

    return p_to
end


function undo_move!(thread::Thread, move::Move, undo::Undo)
    board = thread.board
    thread.movestack.idx -= 1
    thread.piecestack.idx -= 1
    undo_move!(board, move, undo)
    return
end


function undo_move!(board::Board, move::Move, undo::Undo)
    board.checkers = undo.checkers
    board.pinned = undo.pinned
    board.enpass = undo.enpass
    board.castling = undo.castling
    board.halfmovecount = undo.halfmovecount
    board.movecount -= one(UInt16)
    board.hash = undo.hash
    board.psqteval = undo.psqteval
    board.pkhash = undo.pkhash
    switchturn!(board)
    if flag(move) <= __DOUBLE_PAWN
        # If the move was a normal move or double pawn push
        undo_normal!(board, move, undo)
    elseif flag(move) === __ENPASS
        # If the move was enpassant
        undo_enpass!(board, move, undo)
    elseif flag(move) <= __QUEEN_CASTLE
        # If the move was a castling move, fallthrough.
        undo_castle!(board, move, undo)
    else
        # Otherwise, it was a promotion fallthrough.
        undo_promo!(board, move, undo)
    end
    return
end


function undo_normal!(board::Board, move::Move, undo::Undo)
    sqr_from = to(move)
    sqr_to = from(move)

    p_from = piece(board, sqr_from)
    p_to = undo.captured #piece(board, sqr_to)

    bb_from = Bitboard(sqr_from)
    bb_to = Bitboard(sqr_to)

    @inbounds board[type(p_from)] ⊻= bb_from ⊻ bb_to
    @inbounds board[board.turn] ⊻= bb_from ⊻ bb_to
    @inbounds board[sqr_from] = p_to
    @inbounds board[sqr_to] = p_from

    if p_to !== BLANK
        @inbounds board[type(p_to)] ⊻= bb_from
        @inbounds board[!board.turn] ⊻= bb_from
    end
    return
end


function undo_enpass!(board::Board, move::Move, undo::Undo)
    sqr_from = from(move)
    sqr_to = to(move)

    cap_sqr = sqr_to - 24 + (board.turn.val << 4)
    cap_bb = Bitboard(cap_sqr)

    bb_from = Bitboard(sqr_from)
    bb_to = Bitboard(sqr_to)

    @inbounds board[PAWN] ⊻= bb_from ⊻ bb_to ⊻ cap_bb
    @inbounds board[board.turn] ⊻= bb_from ⊻ bb_to
    @inbounds board[!board.turn] ⊻= cap_bb

    @inbounds board[sqr_from] = piece(board, sqr_to)
    @inbounds board[sqr_to] = BLANK
    @inbounds board[cap_sqr] = undo.captured
    return
end


function undo_castle!(board::Board, move::Move, undo::Undo)
    k_from = from(move)
    k_to = to(move)

    if flag(move) === __KING_CASTLE
        r_from = k_from - 3
        r_to = k_from - 1
    else
        r_from = k_from + 4
        r_to = k_from + 1
    end

    r_from_bb = Bitboard(r_from)
    r_to_bb = Bitboard(r_to)
    k_from_bb = Bitboard(k_from)
    k_to_bb = Bitboard(k_to)

    @inbounds board[KING] ⊻= k_from_bb ⊻ k_to_bb
    @inbounds board[ROOK] ⊻= r_from_bb ⊻ r_to_bb

    @inbounds board[board.turn] ⊻= k_from_bb ⊻ k_to_bb ⊻ r_from_bb ⊻ r_to_bb

    @inbounds board[k_from] = makepiece(KING, board.turn)
    @inbounds board[r_from] = makepiece(ROOK, board.turn)
    @inbounds board[k_to] = BLANK
    @inbounds board[r_to] = BLANK
    return
end


function undo_promo!(board::Board, move::Move, undo::Undo)
    sqr_from = from(move)
    sqr_to = to(move)

    bb_from = Bitboard(sqr_from)
    bb_to = Bitboard(sqr_to)

    p_to = undo.captured
    ptype_promo = PieceType((flag(move) >> 12) - 3)

    @inbounds board[PAWN] ⊻= bb_from
    @inbounds board[ptype_promo] ⊻= bb_to
    @inbounds board[board.turn] ⊻= bb_from ⊻ bb_to

    @inbounds board[sqr_from] = makepiece(PAWN, board.turn)
    @inbounds board[sqr_to] = p_to

    if p_to !== BLANK
        @inbounds board[type(p_to)] ⊻= bb_to
        @inbounds board[!board.turn] ⊻= bb_to
    end
    return
end


# "pass" the go, and let out opponent have another move.
function apply_null!(thread::Thread)
    board = thread.board
    push!(thread.movestack, NULL_MOVE)
    push!(thread.piecestack, VOID)
    undo_checkers = board.checkers
    undo_pinned = board.pinned
    undo_castling = board.castling
    undo_enpass = board.enpass
    undo_halfmovecount = board.halfmovecount
    undo_hash = board.hash
    undo_psqteval = board.psqteval
    undo_pkhash = board.pkhash


    # If the position had an enpassant square, set the key as needed, and turn off the enpass square flag.
    if board.enpass !== zero(UInt8)
        board.hash ⊻= zobepkey(board.enpass)
        board.enpass = zero(UInt8)
    end

    # Finishing calculations, for the next turn
    board.hash ⊻= zobturnkey()
    switchturn!(board)

    #board.checkers = kingAttackers(board)
    board.pinned = findpins(board)
    board.movecount += one(board.movecount)
    @inbounds board.history[board.movecount] = board.hash
    return Undo(undo_checkers, undo_pinned, undo_castling, undo_enpass, BLANK, undo_halfmovecount, undo_hash, undo_psqteval, undo_pkhash)
end


function undo_null!(thread::Thread, undo::Undo)
    board = thread.board
    thread.movestack.idx -= 1
    thread.piecestack.idx -= 1
    board.checkers = undo.checkers
    board.pinned = undo.pinned
    board.enpass = undo.enpass
    board.castling = undo.castling
    board.halfmovecount = undo.halfmovecount
    board.movecount -= one(UInt16)
    board.hash = undo.hash
    board.psqteval = undo.psqteval
    board.pkhash = undo.pkhash
    switchturn!(board)
end
