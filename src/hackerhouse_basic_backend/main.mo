// import the custom types we have in Types.mo
import Types "types";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Text "mo:base/Text";
import Cycles "mo:base/ExperimentalCycles";
import Nat "mo:base/Nat";
import Map "mo:map/Map";
import { phash; nhash } "mo:map/Map";
import Vector "mo:vector";
import JSON "mo:serde/JSON";
import Float "mo:base/Float";

actor {

    stable var autoIndex = 0;
    let userIdMap = Map.new<Principal, Nat>();
    let userProfileMap = Map.new<Nat, Text>();
    let userResultsMap = Map.new<Nat, Vector.Vector<Text>>();

    public query ({ caller }) func getUserProfile() : async Result.Result<{ id : Nat; name : Text }, Text> {
        let id = switch (Map.get(userIdMap, phash, caller)) {
            case (null) {
                return #err("User not found");
            };
            case (?id) { id };
        };
        let userProfile = switch (Map.get(userProfileMap, nhash, id)) {
            case (null) {
                return #err("User profile not found");
            };
            case (?name) { name };
        };

        return #ok({ id = id; name = userProfile });
    };

    public shared ({ caller }) func setUserProfile(name : Text) : async Result.Result<{ id : Nat; name : Text }, Text> {
        let userId = switch (Map.get(userIdMap, phash, caller)) {
            case (null) {
                autoIndex += 1;
                Map.set(userIdMap, phash, caller, autoIndex);
                autoIndex;
            };
            case (?id) { id };
        };
        Map.set(userProfileMap, nhash, userId, name);

        return #ok({ id = userId; name = name });
    };

    public shared ({ caller }) func addUserResult(result : Text) : async Result.Result<{ id : Nat; results : [Text] }, Text> {
        let userId = switch (Map.get(userIdMap, phash, caller)) {
            case (null) {
                return #err("User not found");
            };
            case (?id) { id };
        };
        let userResults = switch (Map.get(userResultsMap, nhash, userId)) {
            case (null) {
                Vector.new<Text>();
            };
            case (?results) { results };
        };
        Vector.add(userResults, result);
        Map.set(userResultsMap, nhash, userId, userResults);

        return #ok({ id = userId; results = Vector.toArray(userResults) });
        // return #ok({ id = 123; results = ["fake result"] });
    };

    public query ({ caller }) func getUserResults() : async Result.Result<{ id : Nat; results : [Text] }, Text> {
        let userId = switch (Map.get(userIdMap, phash, caller)) {
            case (null) {
                return #err("User not found");
            };
            case (?id) { id };
        };
        let userResults = switch (Map.get(userResultsMap, nhash, userId)) {
            case (null) {
                return #err("User results not found");
            };
            case (?results) { results };
        };

        return #ok({ id = userId; results = Vector.toArray(userResults) });
        // return #ok({ id = 123; results = ["fake result"] });
    };

    public func outcall_ai_model_for_sentiment_analysis(paragraph : Text) : async Result.Result<{ paragraph : Text; result : Text }, Text> {
        let host = "api-inference.huggingface.co";
        let path = "/models/cardiffnlp/twitter-roberta-base-sentiment-latest";

        let headers = [
            {
                name = "Authorization";
                value = "Bearer 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";
            },
            { name = "Content-Type"; value = "application/json" },
        ];

        let body_json : Text = "{ \"inputs\" : \" " # paragraph # "\" }";

        let text_response = await make_post_http_outcall(host, path, headers, body_json);

        let blob = switch (JSON.fromText(text_response, null)) {
            case (#err(_)) {
                return #err("Failed to parse JSON: " # text_response);
            };
            case (#ok(b)) { b };
        };

        let results : ?[[{ label_ : Text; score : Float }]] = from_candid(blob);
        let parsed_results = switch (results) {
            case (null) {
                return #err("Failed to parse JSON: " # text_response);
            };
            case (?r) { 
                if (r.size() > 0 and r[0].size() > 0) {
                    r[0]
                } else {
                    return #err("Unexpected result structure");
                }
            };
        };

        // Find the sentiment with the highest score
        var highest_score : Float = 0;
        var highest_sentiment : Text = "";
        for (result in parsed_results.vals()) {
            if (result.score > highest_score) {
                highest_score := result.score;
                highest_sentiment := result.label_;
            };
        };

        return #ok({
            paragraph = paragraph;
            result = highest_sentiment # " (confidence: " # Float.toText(highest_score) # ")";
        });
    };

    // NOTE: don't edit below this line

    // Function to transform the HTTP response
    // This function can't be private because it's shared with the IC management canister
    // but it's usage, is not meant to be exposed to the frontend
    public query func transform(raw : Types.TransformArgs) : async Types.CanisterHttpResponsePayload {
        let transformed : Types.CanisterHttpResponsePayload = {
            status = raw.response.status;
            body = raw.response.body;
            headers = [
                {
                    name = "Content-Security-Policy";
                    value = "default-src 'self'";
                },
                { name = "Referrer-Policy"; value = "strict-origin" },
                { name = "Permissions-Policy"; value = "geolocation=(self)" },
                {
                    name = "Strict-Transport-Security";
                    value = "max-age=63072000";
                },
                { name = "X-Frame-Options"; value = "DENY" },
                { name = "X-Content-Type-Options"; value = "nosniff" },
            ];
        };
        transformed;
    };

    func make_post_http_outcall(host : Text, path : Text, headers : [Types.HttpHeader], body_json : Text) : async Text {
        //1. DECLARE IC MANAGEMENT CANISTER
        //We need this so we can use it to make the HTTP request
        let ic : Types.IC = actor ("aaaaa-aa");

        //2. SETUP ARGUMENTS FOR HTTP GET request
        // 2.1 Setup the URL and its query parameters
        let url = "https://" # host # path;

        // 2.2 prepare headers for the system http_request call
        let request_headers = [
            { name = "Host"; value = host # ":443" },
            { name = "User-Agent"; value = "hackerhouse_canister" },
        ];

        let merged_headers = Array.flatten<Types.HttpHeader>([request_headers, headers]);

        // 2.2.1 Transform context
        let transform_context : Types.TransformContext = {
            function = transform;
            context = Blob.fromArray([]);
        };

        // The request body is an array of [Nat8] (see Types.mo) so do the following:
        // 1. Write a JSON string
        // 2. Convert ?Text optional into a Blob, which is an intermediate representation before you cast it as an array of [Nat8]
        // 3. Convert the Blob into an array [Nat8]
        let request_body_as_Blob : Blob = Text.encodeUtf8(body_json);
        let request_body_as_nat8 : [Nat8] = Blob.toArray(request_body_as_Blob);

        // 2.3 The HTTP request
        let http_request : Types.HttpRequestArgs = {
            url = url;
            max_response_bytes = null; //optional for request
            headers = merged_headers;
            // note: type of `body` is ?[Nat8] so it is passed here as "?request_body_as_nat8" instead of "request_body_as_nat8"
            body = ?request_body_as_nat8;
            method = #post;
            transform = ?transform_context;
        };

        //3. ADD CYCLES TO PAY FOR HTTP REQUEST

        //The IC specification spec says, "Cycles to pay for the call must be explicitly transferred with the call"
        //IC management canister will make the HTTP request so it needs cycles
        //See: https://internetcomputer.org/docs/current/motoko/main/cycles

        //The way Cycles.add() works is that it adds those cycles to the next asynchronous call
        //"Function add(amount) indicates the additional amount of cycles to be transferred in the next remote call"
        //See: https://internetcomputer.org/docs/current/references/ic-interface-spec/#ic-http_request
        Cycles.add<system>(230_949_972_000);

        //4. MAKE HTTPS REQUEST AND WAIT FOR RESPONSE
        //Since the cycles were added above, we can just call the IC management canister with HTTPS outcalls below
        let http_response : Types.HttpResponsePayload = await ic.http_request(http_request);

        //5. DECODE THE RESPONSE

        //As per the type declarations in `src/Types.mo`, the BODY in the HTTP response
        //comes back as [Nat8s] (e.g. [2, 5, 12, 11, 23]). Type signature:

        //public type HttpResponsePayload = {
        //     status : Nat;
        //     headers : [HttpHeader];
        //     body : [Nat8];
        // };

        //We need to decode that [Nat8] array that is the body into readable text.
        //To do this, we:
        //  1. Convert the [Nat8] into a Blob
        //  2. Use Blob.decodeUtf8() method to convert the Blob to a ?Text optional
        //  3. We use a switch to explicitly call out both cases of decoding the Blob into ?Text
        let response_body : Blob = Blob.fromArray(http_response.body);
        let decoded_text : Text = switch (Text.decodeUtf8(response_body)) {
            case (null) { "No value returned" };
            case (?y) { y };
        };

        // 6. RETURN RESPONSE OF THE BODY
        return decoded_text;
    };
};
