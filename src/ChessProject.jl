module ChessProject
    using Crayons
    using StaticArrays

    import Base.&, Base.|, Base.~, Base.<<, Base.>>, Base.⊻, Base.!
    import Base.isempty, Base.isone
    import Base.getindex, Base.setindex!, Base.push!
    import Base.iterate, Base.length, Base.eltype, Base.size, Base.IndexStyle
    import Base.show

    include("bitboard.jl")
    include("pieces.jl")
    include("board.jl")
    include("fen.jl")

    include("pawns.jl")
    include("kings.jl")
    include("knights.jl")
    include("magic.jl")
    include("rooks.jl")
    include("bishops.jl")
    include("queens.jl")

    include("attacks.jl")

    include("move.jl")
    include("movegen.jl")

    include("perft.jl")

    include("judge.jl")
    include("monkey.jl")

    include("play.jl")

end
