module CommonCrawl

using AWS
using AWS.S3
using GZip
using HTTPClient
using URIParser

import Base.open

export CommonCrawl, clear_cache, segments, archives, open, read_entry, read_entries

type CommonCrawl
    cloc::String
    debug::Bool
    function CommonCrawl(cache_location::String, debug=false)
        isempty(cache_location) && error("cache location must be set to a valid directory")
        new(cache_location, debug)
    end
end

type ArchiveEntry
    uri::String
    mime::String
    data::Array
end

function clear_cache(cc::CommonCrawl)
    for f in readdir(cc.cloc)
        rm(f)
    end   
end

function clear_cache(cc::CommonCrawl, archive::URI)
    fname = basename(archive.path)
    docsfile = joinpath(cc.cloc, fname)
    isfile(docsfile) && rm(docsfile)
    nothing
end

function segments(cc::CommonCrawl)
    file = joinpath(cc.cloc, "valid_segments.txt")
    if !isfile(file)
        cc.debug && println("fetching valid segments...")
        t1 = time()
        os = open(file, "w")
        ho = HTTPClient.HTTPC.RequestOptions(ostream=os)
        get("http://aws-publicdatasets.s3.amazonaws.com/common-crawl/parse-output/valid_segments.txt", ho)
        close(os)
        cc.debug && println("\tfetched in $(time()-t1)secs")
    end
    segments = String[]
    open(file) do f
        for str in readlines(f)
            push!(segments, chomp(str))
        end
    end
    segments
end

function archives(cc:CommonCrawl, segment::String)
    file = joinpath(cc.cloc, string("segment_list_",segment,".txt"))
    arcnames = URI[]
    if !isfile(file)
        cc.debug && println("listing segment $segment")
        t1 = time()
        env = AWSEnv(timeout=60.0)
        segname = string("common-crawl/parse-output/segment/", segment)
        os = open(file, "w")
        opts = GetBucketOptions(prefix=segname)
        while true
            resp = S3.get_bkt(env, "aws-publicdatasets", options=opts)
            for elem in resp.obj.contents
                if endswith(elem.key, ".arc.gz")
                    uri_str = string("http://aws-publicdatasets.s3.amazonaws.com/", elem.key)
                    push!(arcnames, URI(uri_str))
                    println(os, uri_str)
                end
                opts.marker = elem.key
            end
            !resp.obj.isTruncated && break
        end
        close(os)
        cc.debug && println("\tfetched in $(time()-t1)secs")
    else
        cc.debug && println("opening cached file [$(file)]")
        open(file) do f
            for str in readlines(f)
                push!(arcnames, URI(chomp(str)))
            end
        end
    end
    cc.debug && println("$(length(arcnames)) archives in segment $(segment)")
    arcnames
end

function archives(cc::CommonCrawl, count::Int=0)
    arcs = URI[]
    for seg in segments(cc)
        arcs_in_seg = cc_archives_in_segment(segment)
        append!(arcs, arcs_in_seg)
        (count > 0) && (length(arcs) >= count) && break
    end
    (count == 0) ? arcs : arcs[1:count]
end

function open(cc::CommonCrawl, archive::URI)
    fname = basename(archive.path)
    docsfile = joinpath(cc.cloc, fname)
    cc.debug && println("opening $s3Uri. ($docsfile)")
    if !isfile(docsfile)
        cc.debug && println("\tdownloading $s3Uri to $docsfile")
        t1 = time()
        os = open(docsfile, "w")
        ho = HTTPClient.HTTPC.RequestOptions(ostream=os)
        get(string(s3Uri), ho)
        close(os)
        cc.debug && println("\tdownloaded in $(time()-t1)secs")
    end
    GZip.open(docsfile, "r")
end


function read_entry(cc::CommonCrawl, f::IO, mime_part::String="")
    arc = ArchiveEntry("","",[])
    while true
        l = readline(f)
        while !eof(f) && isempty(l)
            l = readline(f)
        end
        eof(f) && isempty(l) && break
        vs = split(l)

        url = vs[1]
        mime = vs[4]
        len = parseint(vs[5])

        if !isempty(mime_part) && !beginswith(mime, mime_part)
            skip(f, len)
            continue 
        end
        arc.data = read(f, Array(Uint8, len))
        arc.uri = uri
        arc.mime = mime
    end
    arc
end

function read_entries(cc::CommonCrawl, f::IO, mime_part::String="", num_entries::Int=0)
    arcs = ArchiveEntry[]
    while !eof(f) 
        (num_entries > 0) && (length(arc) >= num_entries) && break
        arc = read_entry(cc, f, mime_part)
        isempty(arc.data) && continue
        push!(arcs, arc)
    end
    arcs
end

end

