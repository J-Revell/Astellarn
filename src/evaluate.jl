#====================== Auxilliary precomputation =============================#
"""
    EvalInfo

EvalAux is an auxilliary data structure for storing useful computations for the evaluation of the board.
"""
struct EvalInfo
    wrammedpawns::Bitboard
    brammedpawns::Bitboard
    wmobility::Bitboard
    bmobility::Bitboard
    stage::Int
end


"""
    EvalAttackInfo

EvalAux is an auxilliary data structure for storing useful computations for the evaluation of the board.
"""
mutable struct EvalAttackInfo
    wpawnattacks::Bitboard
    wknightattacks::Bitboard
    wbishopattacks::Bitboard
    wrookattacks::Bitboard
    wqueenattacks::Bitboard
    wkingattacks::Bitboard
    bpawnattacks::Bitboard
    bknightattacks::Bitboard
    bbishopattacks::Bitboard
    brookattacks::Bitboard
    bqueenattacks::Bitboard
    bkingattacks::Bitboard
end


function initEvalInfo(board::Board)
    # extract pawn positions
    wpawns = white(board) & pawns(board)
    bpawns = black(board) & pawns(board)

    # check for rammed pawns
    wrammedpawns = pawnAdvance(bpawns, wpawns, BLACK)
    brammedpawns = pawnAdvance(wpawns, bpawns, WHITE)
    # wrammedpawns = bswap(bpawns) & wpawns
    # brammedpawns = bswap(wrammedpawns)

    # generate list of all positions attacked by a pawn
    wpawnattacks = pawnCapturesWhite(wpawns, FULL)
    bpawnattacks = pawnCapturesBlack(bpawns, FULL)

    # generate list of all positions attacked by a knight
    wknightattacks = bknightattacks = EMPTY #knightMove_all(wknights)
    #bknightattacks = EMPTY #knightMove_all(bknights)

    wbishopattacks = bbishopattacks = EMPTY
    #bbishopattacks = EMPTY

    wrookattacks = brookattacks = EMPTY
    #brookattacks = EMPTY

    wqueenattacks = bqueenattacks = EMPTY
    #bqueenattacks = EMPTY

    wkingattacks = bkingattacks = EMPTY
    #bkingattacks = EMPTY

    # mobility regions
    wmobility = ~((white(board) & kings(board)) | bpawnattacks)
    bmobility = ~((black(board) & kings(board)) | wpawnattacks)

    gamestage = stage(board)

    # wattacks = [wpawnattacks, wknightattacks, wbishopattacks, wrookattacks, wqueenattacks, wkingattacks]
    # battacks = [bpawnattacks, bknightattacks, bbishopattacks, brookattacks, bqueenattacks, bkingattacks]
    # allattacks = [EMPTY, EMPTY]

    ei = EvalInfo(wrammedpawns, brammedpawns, wmobility, bmobility, gamestage)
    ea = EvalAttackInfo(wpawnattacks, wknightattacks, wbishopattacks, wrookattacks, wqueenattacks, wkingattacks, bpawnattacks, bknightattacks, bbishopattacks, brookattacks, bqueenattacks, bkingattacks)
    ei, ea
end


#============================== Game stage functions ==========================#


function stage(board::Board)
    stage = 24 - 4count(queens(board)) - 2count(rooks(board)) - count(knights(board) | bishops(board))
    stage = fld(stage * 256 + 12, 24)
end


#=============================== Endgame scoring scaling ======================#


function scale_factor(board::Board, eval::Int)
    if isone(board[WHITEBISHOP]) && isone(board[BLACKBISHOP]) && isone(bishops(board) & LIGHT)
        if isempty(knights(board) | rooklike(board))
            return SCALE_OCB_BISHOPS
        end
        if isempty(rooklike(board)) && isone(board[WHITEKNIGHT]) && isone(board[BLACKKNIGHT])
            return SCALE_OCB_ONE_KNIGHT
        end
        if isempty(knights(board) | queens(board)) && isone(board[WHITEROOK]) && isone(board[BLACKROOK])
            return SCALE_OCB_ONE_ROOK
        end
    end
    if (eval > 0) && (count(white(board)) == 2) && ismany(board[WHITEKNIGHT] | board[WHITEBISHOP])
        return SCALE_DRAW
    elseif (eval < 0) && (count(black(board)) == 2) && ismany(board[BLACKKNIGHT] | board[BLACKBISHOP])
        return SCALE_DRAW
    end
    return SCALE_NORMAL
end


#=============================== Main evaluation ==============================#


"""
    evaluate(board)

Naive evaluation function to get the code development going.
"""
function evaluate(board::Board, ptable::PawnKingTable)
    ei, ea = initEvalInfo(board)

    score = 0
    score += board.psqteval

    if (pt_entry = get(ptable, board.pkhash, false)) !== false
        score += pt_entry.score
    end

    # v = fld(scoreEG(score) + scoreMG(score), 2)
    # if abs(v) > LAZY_THRESH
    #     if board.turn == WHITE
    #         return v
    #     else
    #         return -v
    #     end
    # end

    if pt_entry == false
        score += evaluate_pawns(board, ei, ea, ptable)
    end
    score += evaluate_knights(board, ei, ea)
    score += evaluate_bishops(board, ei, ea)
    score += evaluate_rooks(board, ei, ea)
    score += evaluate_queens(board, ei, ea)
    score += evaluate_kings(board, ei, ea)


    score += evaluate_pins(board)
    score += evaluate_space(board, ei, ea)
    score += evaluate_threats(board, ei, ea)

    scale_f = scale_factor(board, scoreEG(score))

    eval = (256 - ei.stage) * scoreMG(score) + ei.stage * scoreEG(score) * fld(scale_f, SCALE_NORMAL)
    eval = fld(eval, 256)

    if board.turn == WHITE
        eval += TEMPO_BONUS
        return eval
    else
        eval -= TEMPO_BONUS
        return -eval
    end
end


function evaluate_pawns(board::Board, ei::EvalInfo, ea::EvalAttackInfo, pktable::PawnKingTable)

    w_pawns = white(board) & pawns(board)
    b_pawns = black(board) & pawns(board)

    w_king = square(white(board) & kings(board))
    b_king = square(black(board) & kings(board))

    score = 0

    @inbounds for pawn in w_pawns
        bonus = 0
        file = fileof(pawn)
        rank = rankof(pawn)
        factor = 5 * rank - 13
        # Passed pawns
        if isempty(b_pawns & PASSED_PAWN_MASKS[1][pawn])
            bonus += PASS_PAWN_THREAT[rank]
            block_sqr = pawn + 8
            if rank > 3
                bonus += makescore(0, (fld(min(DISTANCE_BETWEEN[block_sqr, b_king],5)*19, 4) - min(DISTANCE_BETWEEN[block_sqr, w_king],5)*2)*factor)
                if rank !== 7
                    block_sqr_2 = block_sqr + 8
                    bonus -= makescore(0, DISTANCE_BETWEEN[block_sqr_2, w_king]*factor)
                end
            end
            if board[block_sqr] == WHITEPAWN
                bonus -= makescore(50, 50)
            end
            score += bonus
        end
        # Isolated pawns
        if isempty(NEIGHBOUR_FILE_MASKS[file] & w_pawns & ~FILE[file])
            score -= ISOLATED_PAWN_PENALTY
        end
        # Double pawns
        if ismany(w_pawns & FILE[file])
            score -= DOUBLE_PAWN_PENALTY
        end

        file_psqt = FILE_TO_QSIDE_MAP[file]
        if !isempty(CONNECTED_PAWN_MASKS[1][pawn] & w_pawns)
            score += CONNECTED_PAWN_PSQT[rank][file_psqt]
        end
    end

    @inbounds for pawn in b_pawns
        bonus = 0
        file = fileof(pawn)
        rank = 9 - rankof(pawn)
        factor = 5 * rank - 13
        # Passed pawns
        if isempty(w_pawns & PASSED_PAWN_MASKS[2][pawn])
            bonus += PASS_PAWN_THREAT[rank]
            block_sqr = pawn - 8
            if rank > 3
                bonus += makescore(0, (fld(min(DISTANCE_BETWEEN[block_sqr, w_king],5)*19, 4) - min(DISTANCE_BETWEEN[block_sqr, b_king],5)*2)*factor)
                if rank !== 7
                    block_sqr_2 = block_sqr - 8
                    bonus -= makescore(0, DISTANCE_BETWEEN[block_sqr_2, b_king]*factor)
                end
            end
            if board[block_sqr] == BLACKPAWN
                bonus -= makescore(50, 50)
            end
            score -= bonus
        end
        # Isolated pawns
        if isempty(NEIGHBOUR_FILE_MASKS[file] & b_pawns & ~FILE[file])
            score += ISOLATED_PAWN_PENALTY
        end
        # Double pawns
        if ismany(b_pawns & FILE[file])
            score += DOUBLE_PAWN_PENALTY
        end

        file_psqt = FILE_TO_QSIDE_MAP[file]
        if !isempty(CONNECTED_PAWN_MASKS[2][pawn] & b_pawns)
            score -= CONNECTED_PAWN_PSQT[rank][file_psqt]
        end
    end

    if isempty(pawns(board) & KINGFLANK[fileof(w_king)])
        score -= PAWNLESS_FLANK
    end
    if isempty(pawns(board) & KINGFLANK[fileof(b_king)])
        score += PAWNLESS_FLANK
    end


    pktable[board.pkhash] = PKT_Entry(score)
    return score
end


function evaluate_knights(board::Board, ei::EvalInfo, ea::EvalAttackInfo)
    w_knights = white(board) & knights(board)
    b_knights = black(board) & knights(board)

    w_pawns = pawns(board) & white(board)
    b_pawns = pawns(board) & black(board)

    w_king_sqr = square(kings(board) & white(board))
    b_king_sqr = square(kings(board) & black(board))

    score = 0

    w_outposts = (RANK_4 | RANK_5 | RANK_6) & ea.wpawnattacks & ~ea.bpawnattacks
    @inbounds for knight in w_knights
        attacks = knightMoves(knight)
        ea.wknightattacks |= attacks
        score += KNIGHT_MOBILITY[count(attacks & ei.wmobility) + 1]
        score -= MINOR_KING_PROTECTION * DISTANCE_BETWEEN[w_king_sqr, knight]
    end
    # Score knight outposts
    score += count(w_outposts & w_knights) * KNIGHT_OUTPOST_BONUS
    # Score reachable knight outposts
    score += count(w_outposts & ea.wknightattacks & ~white(board)) * KNIGHT_POTENTIAL_OUTPOST_BONUS
    # Score knights behind pawns
    score += count((w_knights << 8) & w_pawns) * PAWN_SHIELD_BONUS


    b_outposts = (RANK_3 | RANK_4 | RANK_5) & ~ea.wpawnattacks & ea.bpawnattacks
    @inbounds for knight in b_knights
        attacks = knightMoves(knight)
        ea.bknightattacks |= attacks
        score -= KNIGHT_MOBILITY[count(attacks & ei.bmobility) + 1]
        score += MINOR_KING_PROTECTION * DISTANCE_BETWEEN[b_king_sqr, knight]
    end
    # Score knight outposts
    score -= count(b_outposts & b_knights) * KNIGHT_OUTPOST_BONUS
    # Score reachable knight outposts
    score -= count(b_outposts & ea.bknightattacks & ~black(board)) * KNIGHT_POTENTIAL_OUTPOST_BONUS
    # Score knights behind pawns
    score -= count((b_knights >> 8) & b_pawns) * PAWN_SHIELD_BONUS

    # bonus for knights in rammed positions
    num_rammed = count(ei.wrammedpawns)
    score += div(count(w_knights) * num_rammed^2, 4) * KNIGHT_RAMMED_BONUS
    score -= div(count(b_knights) * num_rammed^2, 4) * KNIGHT_RAMMED_BONUS

    # Evaluate trapped knights.
    for trap in KNIGHT_TRAP_PATTERNS[1]
        if ((b_pawns & trap.pawnmask) == trap.pawnmask) && isone(w_knights & trap.minormask)
            score -= KNIGHT_TRAP_PENALTY
        end
    end
    for trap in KNIGHT_TRAP_PATTERNS[2]
        if ((w_pawns & trap.pawnmask) == trap.pawnmask) && isone(b_knights & trap.minormask)
            score += KNIGHT_TRAP_PENALTY
        end
    end

    score
end


function evaluate_bishops(board::Board, ei::EvalInfo, ea::EvalAttackInfo)
    w_bishops = white(board) & bishops(board)
    b_bishops = black(board) & bishops(board)

    w_pawns = pawns(board) & white(board)
    b_pawns = pawns(board) & black(board)

    w_king_sqr = square(kings(board) & white(board))
    b_king_sqr = square(kings(board) & black(board))

    score = 0

    attacks = EMPTY
    occ = occupied(board)

    w_outposts = (RANK_4 | RANK_5 | RANK_6) & ea.wpawnattacks & ~ea.bpawnattacks
    @inbounds for bishop in w_bishops
        attacks = bishopMoves(bishop, occ)
        ea.wbishopattacks |= attacks
        score += BISHOP_MOBILITY[count(attacks & ei.wmobility) + 1]
        if ismany(attacks & CENTRAL_SQUARES)
            score += BISHOP_CENTRAL_CONTROL
        end
        score -= MINOR_KING_PROTECTION * DISTANCE_BETWEEN[w_king_sqr, bishop]
    end
    # Outpost bonus
    score += count(w_outposts & w_bishops) * BISHOP_OUTPOST_BONUS
    # Add a bonus for being behind a pawn.
    score += count((w_bishops << 8) & w_pawns) * PAWN_SHIELD_BONUS


    b_outposts = (RANK_3 | RANK_4 | RANK_5) & ~ea.wpawnattacks & ea.bpawnattacks
    @inbounds for bishop in b_bishops
        attacks = bishopMoves(bishop, occ)
        ea.bbishopattacks |= attacks
        score -= BISHOP_MOBILITY[count(attacks & ei.bmobility) + 1]
        if ismany(attacks & CENTRAL_SQUARES)
            score -= BISHOP_CENTRAL_CONTROL
        end
        score += MINOR_KING_PROTECTION * DISTANCE_BETWEEN[b_king_sqr, bishop]
    end
    score -= count(b_outposts & b_bishops) * BISHOP_OUTPOST_BONUS
    # Add a bonus for being behind a pawn
    score -= count((b_bishops >> 8) & b_pawns) * PAWN_SHIELD_BONUS

    for trap in BISHOP_TRAP_PATTERNS[1]
        if ((b_pawns & trap.pawnmask) == trap.pawnmask) && !isempty(w_bishops & trap.minormask)
            score -= BISHOP_TRAP_PENALTY
        end
    end
    for trap in BISHOP_TRAP_PATTERNS[2]
        if ((w_pawns & trap.pawnmask) == trap.pawnmask) && !isempty(b_bishops & trap.minormask)
            score += BISHOP_TRAP_PENALTY
        end
    end

    # bishop pair
    if count(w_bishops) >= 2
        score += BISHOP_PAIR_BONUS
    end
    if count(b_bishops) >= 2
        score -= BISHOP_PAIR_BONUS
    end

    # penalty for bishops on colour of own pawns
    if !isempty(w_bishops & LIGHT)
        score -= BISHOP_COLOR_PENALTY * count(w_pawns & LIGHT)
        score -= BISHOP_RAMMED_COLOR_PENALTY * count(ei.wrammedpawns & LIGHT)
    end
    if !isempty(w_bishops & DARK)
        score -= BISHOP_COLOR_PENALTY * count(w_pawns & DARK)
        score -= BISHOP_RAMMED_COLOR_PENALTY * count(ei.wrammedpawns & DARK)
    end
    if !isempty(b_bishops & LIGHT)
        score += BISHOP_COLOR_PENALTY * count(b_pawns & LIGHT)
        score += BISHOP_RAMMED_COLOR_PENALTY * count(ei.brammedpawns & LIGHT)
    end
    if !isempty(b_bishops & DARK)
        score += BISHOP_COLOR_PENALTY * count(b_pawns & DARK)
        score += BISHOP_RAMMED_COLOR_PENALTY * count(ei.brammedpawns & DARK)
    end

    score
end


function evaluate_rooks(board::Board, ei::EvalInfo, ea::EvalAttackInfo)
    w_rooks = (white(board) & rooks(board))
    b_rooks = (black(board) & rooks(board))

    score = 0

    occ = occupied(board)
    @inbounds for rook in w_rooks
        rfile = file(rook)
        if isempty(rfile & pawns(board))
            score += ROOK_OPEN_FILE_BONUS
        elseif isempty(rfile & white(board) & pawns(board))
            score += ROOK_SEMIOPEN_FILE_BONUS
        end
        if !isempty(rfile & queens(board))
            score += ROOK_ON_QUEEN_FILE
        end
        attacks = rookMoves(rook, occ)
        ea.wrookattacks |= attacks
        mob_cnt = count(attacks & ei.wmobility) + 1
        score += ROOK_MOBILITY[mob_cnt]
    end

    @inbounds for rook in b_rooks
        rfile = file(rook)
        if isempty(rfile & pawns(board))
            score -= ROOK_OPEN_FILE_BONUS
        elseif isempty(rfile & black(board) & pawns(board))
            score -= ROOK_SEMIOPEN_FILE_BONUS
        end
        if !isempty(rfile & queens(board))
            score -= ROOK_ON_QUEEN_FILE
        end
        attacks = rookMoves(rook, occ)
        ea.brookattacks |= attacks
        mob_cnt = count(attacks & ei.bmobility) + 1
        score -= ROOK_MOBILITY[mob_cnt]
    end

    score
end


function evaluate_queens(board::Board, ei::EvalInfo, ea::EvalAttackInfo)
    w_queens = board[WHITEQUEEN]
    b_queens = board[BLACKQUEEN]

    score = 0

    occ = occupied(board)

    @inbounds for queen in w_queens
        attacks = queenMoves(queen, occ)
        ea.wqueenattacks |= attacks
        score += QUEEN_MOBILITY[count(attacks & ei.wmobility) + 1]
    end

    @inbounds for queen in b_queens
        attacks = queenMoves(queen, occ)
        ea.bqueenattacks |= attacks
        score -= QUEEN_MOBILITY[count(attacks & ei.bmobility) + 1]
    end

    score
end


function evaluate_kings(board::Board, ei::EvalInfo, ea::EvalAttackInfo)
    w_king = board[WHITEKING]
    b_king = board[BLACKKING]
    w_king_sqr = square(w_king)
    b_king_sqr = square(b_king)
    ea.wkingattacks |= kingMoves(w_king_sqr)
    ea.bkingattacks |= kingMoves(b_king_sqr)

    king_safety = 0
    score = 0

    if cancastlekingside(board, WHITE)
        score += CASTLE_OPTION_BONUS
    end
    if cancastlequeenside(board, WHITE)
        score += CASTLE_OPTION_BONUS
    end
    if cancastlekingside(board, BLACK)
        score -= CASTLE_OPTION_BONUS
    end
    if cancastlequeenside(board, BLACK)
        score -= CASTLE_OPTION_BONUS
    end


    # Increase king safety for each pawn surrounding him
    # king_safety += count(ea.wkingattacks & white(board) & pawns(board)) * KING_PAWN_SHIELD_BONUS
    # king_safety -= count(ea.bkingattacks & black(board) & pawns(board)) * KING_PAWN_SHIELD_BONUS
    # if isempty(pawns(board) & KINGFLANK[fileof(w_king_sqr)])
    #     score -= PAWNLESS_FLANK
    # end
    # if isempty(pawns(board) & KINGFLANK[fileof(b_king_sqr)])
    #     score += PAWNLESS_FLANK
    # end


    # decrease king safety if on an open file, with enemy rooks or queens on the board.
    if !isempty((black(board) & rooks(board)) | board[BLACKQUEEN]) && isempty(file(w_king_sqr) & pawns(board))
        king_safety -= 15
    end
    if !isempty((white(board) & rooks(board)) | board[WHITEQUEEN]) && isempty(file(b_king_sqr) & pawns(board))
        king_safety += 15
    end

    # decrease safety if neighbouring squares are attacked
    b_attacks = ea.bpawnattacks | ea.bknightattacks | ea.bbishopattacks | ea.brookattacks | ea.bqueenattacks
    w_attacks = ea.wpawnattacks | ea.wknightattacks | ea.wbishopattacks | ea.wrookattacks | ea.wqueenattacks
    king_safety -= 9 * count(b_attacks & ea.wkingattacks) * div(15, (count(ea.wkingattacks) + 1))
    king_safety += 9 * count(w_attacks & ea.bkingattacks) * div(15, (count(ea.bkingattacks) + 1))

    # Score the number of attacks on our king's flank
    score -= count(b_attacks & KINGFLANK[fileof(w_king_sqr)]) * KING_FLANK_ATTACK
    score += count(w_attacks & KINGFLANK[fileof(b_king_sqr)]) * KING_FLANK_ATTACK

    eval = king_safety
    score + makescore(eval, eval)
end


function evaluate_pins(board::Board)
    eval = 0

    # switch turn and find all pins
    board.turn = !board.turn
    opp_pinned = findpins(board)
    board.turn = !board.turn

    if board.turn == WHITE
        eval -= count(board.pinned) * PIN_BONUS
        eval += count(opp_pinned) * PIN_BONUS
    else
        eval += count(board.pinned) * PIN_BONUS
        eval -= count(opp_pinned) * PIN_BONUS
    end

    # specific additional pin bonus
    eval -= count(pinned(board) & queens(board)) * 30
    eval += count(opp_pinned & queens(board)) * 30
    eval -= count(pinned(board) & rooks(board)) * 10
    eval += count(opp_pinned & rooks(board)) * 10

    makescore(eval, eval)
end


function evaluate_space(board::Board, ei::EvalInfo, ea::EvalAttackInfo)
    eval = 0

    w_filter = (RANK_2 | RANK_3 | RANK_4) & CENTERFILES
    b_filter = (RANK_5 | RANK_6 | RANK_7) & CENTERFILES
    w_attacks = ea.wpawnattacks | ea.wknightattacks | ea.wbishopattacks | ea.wrookattacks | ea.wqueenattacks | ea.wkingattacks
    b_attacks = ea.bpawnattacks | ea.bknightattacks | ea.bbishopattacks | ea.brookattacks | ea.bqueenattacks | ea.bkingattacks
    eval += count(w_filter & ~b_attacks) * SPACE_BONUS
    eval -= count(b_filter & ~w_attacks) * SPACE_BONUS

    makescore(eval, eval)
end


function evaluate_threats(board::Board, ei::EvalInfo, ea::EvalAttackInfo)
    w_attacks = ea.wpawnattacks
    w_double_attacks = w_attacks & ea.wknightattacks
    w_attacks |= ea.wknightattacks
    w_double_attacks |= w_attacks & ea.wbishopattacks
    w_attacks |= ea.wbishopattacks
    w_double_attacks |= w_attacks & ea.wrookattacks
    w_attacks |= ea.wrookattacks
    w_double_attacks |= w_attacks & ea.wqueenattacks
    w_attacks |= ea.wqueenattacks
    w_double_attacks |= w_attacks & ea.wkingattacks
    w_attacks |= ea.wkingattacks

    b_attacks = ea.bpawnattacks
    b_double_attacks = b_attacks & ea.bknightattacks
    b_attacks |= ea.bknightattacks
    b_double_attacks |= b_attacks & ea.bbishopattacks
    b_attacks |= ea.bbishopattacks
    b_double_attacks |= b_attacks & ea.brookattacks
    b_attacks |= ea.brookattacks
    b_double_attacks |= b_attacks & ea.bqueenattacks
    b_attacks |= ea.bqueenattacks
    b_double_attacks |= b_attacks & ea.bkingattacks
    b_attacks |= ea.bkingattacks

    occ = occupied(board)

    score = 0

    #=================== below are newer evaluation terms ==================#
    # if board.turn == WHITE
    #     weak = b_attacks & (~w_attacks | ea.wqueenattacks | ea.wkingattacks) & ~w_double_attacks
    # else
    #     weak = w_attacks & (~b_attacks | ea.bqueenattacks | ea.bkingattacks)
    # end


    #========================= Evaluation w.r.t. white ========================#
    # strongly protected by the enemy.
    strongly_protected = ea.bpawnattacks | (b_double_attacks & ~w_double_attacks)
    # well defended by the enemy
    defended = (black(board) & ~pawns(board)) & strongly_protected
    # not well defended by the enemy
    weak = black(board) & ~strongly_protected & w_attacks

    # Case where our opponent is hanging pieces
    case = ~b_attacks | ((black(board) & ~pawns(board)) & w_double_attacks)
    # Bonus if opponent is hanging pieces
    score += HANGING_BONUS * count(weak & case)

    if !isempty(weak & ea.wkingattacks)
        score += THREAT_BY_KING
    end

    # Case where our opponent is defended or weak, and attacked by a bishop or knight.
    case = (defended | weak) & (ea.wknightattacks | ea.wbishopattacks)
    case_pawns = count(case & pawns(board))
    case_knights = count(case & knights(board))
    case_bishops = count(case & bishops(board))
    case_rooks = count(case & rooks(board))
    case_queens = count(case & queens(board))
    score += THREAT_BY_MINOR[1] * case_pawns
    score += THREAT_BY_MINOR[2] * case_knights
    score += THREAT_BY_MINOR[3] * case_bishops
    score += THREAT_BY_MINOR[4] * case_rooks
    score += THREAT_BY_MINOR[5] * case_queens

    # Case where our opponent is weak and attacked by our rook
    case = weak & ea.wrookattacks
    case_pawns = count(case & pawns(board))
    case_knights = count(case & knights(board))
    case_bishops = count(case & bishops(board))
    case_rooks = count(case & rooks(board))
    case_queens = count(case & queens(board))
    score += THREAT_BY_ROOK[1] * case_pawns
    score += THREAT_BY_ROOK[2] * case_knights
    score += THREAT_BY_ROOK[3] * case_bishops
    score += THREAT_BY_ROOK[4] * case_rooks
    score += THREAT_BY_ROOK[5] * case_queens

    # Case where we get a bonus for restricting our opponent
    case = b_attacks & ~strongly_protected & w_attacks
    score += count(case) * RESTRICTION_BONUS


    safe = ~b_attacks | w_attacks
    case = pawns(board) & white(board) & safe
    case = pawnCapturesWhite(case, black(board) & ~pawns(board))
    score += THREAT_BY_PAWN * count(case)

    # Evaluate if there are pieces that can reach a checking square, while being safe.
    # King Danger evaluations.
    b_king_sqr = square(black(board) & kings(board))
    safe = ~white(board) & (~b_attacks | (weak & w_double_attacks))
    knightcheck_sqrs = knightMoves(b_king_sqr) & safe & ea.wknightattacks
    bishopcheck_sqrs = bishopMoves(b_king_sqr, occ) & safe & ea.wbishopattacks
    rookcheck_sqrs   = rookMoves(b_king_sqr, occ) & safe & ea.wrookattacks
    queencheck_sqrs  = (rookcheck_sqrs | bishopcheck_sqrs) & safe & ea.wqueenattacks
    king_danger = 0
    if !isempty(knightcheck_sqrs)
        king_danger += KNIGHT_SAFE_CHECK
    end
    if !isempty(bishopcheck_sqrs)
        king_danger += BISHOP_SAFE_CHECK
    end
    if !isempty(rookcheck_sqrs)
        king_danger += ROOK_SAFE_CHECK
    end
    if !isempty(queencheck_sqrs)
        king_danger += QUEEN_SAFE_CHECK
    end
    if isempty(board[WHITEQUEEN])
        king_danger -= 100
    end
    if isempty(board[WHITEROOK])
        king_danger -= 50
    end
    if isempty(board[WHITEBISHOP])
        king_danger -= 20
    end
    if isempty(board[WHITEKNIGHT])
        king_danger -= 20
    end
    if king_danger > 0
        score += makescore(king_danger, fld(king_danger, 2))
    end


    #========================= Evaluation w.r.t. black ========================#

    # strongly protected by the enemy.
    strongly_protected = ea.wpawnattacks | (w_double_attacks & ~b_double_attacks)
    # well defended by the enemy
    defended = (white(board) & ~pawns(board)) & strongly_protected
    # not well defended by the enemy
    weak = white(board) & ~strongly_protected & b_attacks

    # Case where our opponent is hanging pieces
    case = ~w_attacks | ((white(board) & ~pawns(board)) & b_double_attacks)
    # Bonus if opponent is hanging pieces
    score -= HANGING_BONUS * count(weak & case)

    if !isempty(weak & ea.bkingattacks)
        score -= THREAT_BY_KING
    end

    # Case where our opponent is defended or weak, and attacked by a bishop or knight.
    case = (defended | weak) & (ea.bknightattacks | ea.bbishopattacks)
    case_pawns = count(case & pawns(board))
    case_knights = count(case & knights(board))
    case_bishops = count(case & bishops(board))
    case_rooks = count(case & rooks(board))
    case_queens = count(case & queens(board))
    score -= THREAT_BY_MINOR[1] * case_pawns
    score -= THREAT_BY_MINOR[2] * case_knights
    score -= THREAT_BY_MINOR[3] * case_bishops
    score -= THREAT_BY_MINOR[4] * case_rooks
    score -= THREAT_BY_MINOR[5] * case_queens

    # Case where our opponent is weak and attacked by our rook
    case = weak & ea.brookattacks
    case_pawns = count(case & pawns(board))
    case_knights = count(case & knights(board))
    case_bishops = count(case & bishops(board))
    case_rooks = count(case & rooks(board))
    case_queens = count(case & queens(board))
    score -= THREAT_BY_ROOK[1] * case_pawns
    score -= THREAT_BY_ROOK[2] * case_knights
    score -= THREAT_BY_ROOK[3] * case_bishops
    score -= THREAT_BY_ROOK[4] * case_rooks
    score -= THREAT_BY_ROOK[5] * case_queens

    # Case where we get a bonus for restricting our opponent
    case = b_attacks & ~strongly_protected & w_attacks
    score -= count(case) * RESTRICTION_BONUS

    safe = ~w_attacks | b_attacks
    case = pawns(board) & black(board) & safe
    case = pawnCapturesBlack(case, white(board) & ~pawns(board))
    score -= THREAT_BY_PAWN * count(case)

    # Evaluate if there are pieces that can reach a checking square, while being safe.
    # King Danger evaluations.
    w_king_sqr = square(white(board) & kings(board))
    safe = ~black(board) & (~w_attacks | (weak & b_double_attacks))
    knightcheck_sqrs = knightMoves(w_king_sqr) & safe & ea.bknightattacks
    bishopcheck_sqrs = bishopMoves(w_king_sqr, occ) & safe & ea.bbishopattacks
    rookcheck_sqrs   = rookMoves(w_king_sqr, occ) & safe & ea.brookattacks
    queencheck_sqrs  = (rookcheck_sqrs | bishopcheck_sqrs) & safe & ea.bqueenattacks
    king_danger = 0
    if !isempty(knightcheck_sqrs)
        king_danger += KNIGHT_SAFE_CHECK
    end
    if !isempty(bishopcheck_sqrs)
        king_danger += BISHOP_SAFE_CHECK
    end
    if !isempty(rookcheck_sqrs)
        king_danger += ROOK_SAFE_CHECK
    end
    if !isempty(queencheck_sqrs)
        king_danger += QUEEN_SAFE_CHECK
    end
    if isempty(board[BLACKQUEEN])
        king_danger -= 100
    end
    if isempty(board[BLACKROOK])
        king_danger -= 50
    end
    if isempty(board[BLACKBISHOP])
        king_danger -= 20
    end
    if isempty(board[BLACKKNIGHT])
        king_danger -= 20
    end
    if king_danger > 0
        score -= makescore(king_danger, fld(king_danger, 2))
    end

    score
end
