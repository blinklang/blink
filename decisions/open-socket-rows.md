[< All Decisions](../DECISIONS.md)

# Effect Rows for Methods on Open Sockets — Design Rationale

### Panel Deliberation

The ticket (verbatim):

> Spec: effect rows for I/O methods on open sockets (UDP and Unix-domain)
>
> From the effect-tracked builtins panel: §4.4.6 gives rows for unix_listen/unix_connect and UDP bind, but not for UdpSocket recv_from/send_to/local_addr/set_timeout/close or UnixListener.accept beyond Net.Listen and UnixStream read_line/write/close. Rule 2 (sound upper bound) needs each row stated. The spec now says these rows are not yet given.

Moderator triage found that the ticket lists `send_to` as missing, but §4.4.6 already gave it `! Net.Connect`; the ticket also omits `UnixListener.close`. Eight methods had no row: `UdpSocket.recv_from`, `local_addr`, `set_timeout`, `close`; `UnixListener.close`; `UnixStream.read_line`, `write`, `close`. `UnixStream` came from two makers with different rows (`unix_connect ! Net.Connect` and `accept ! Net.Listen`). Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in three phases. Phase D was not triggered. Quoted text is each panelist's own words. Each quote is a whole paragraph or list item of the panel record, or a line range of one; "…" marks a cut.

Questions:

- Q1: the rows. A method on an open socket gets the row of the function that made the socket; a method that sends to a peer the caller names gets `Net.Connect`. `UdpSocket.recv_from`, `local_addr`, `set_timeout`, `close` and `UnixListener.close` get `Net.Listen`. `accept` returns a new stream type whose methods get `Net.Listen`; `unix_connect` keeps `UnixStream`, whose methods get `Net.Connect`. The §4.4.6 examples stay as written, and a client example is added.
- Q2: the rule text. **M:** the maker row, and `Net.Connect` in its place for a method that sends to a caller-given peer address. **A:** the act clause first (a named peer is `Net.Connect`; traffic from peers the caller does not name is `Net.Listen`), then the maker row.
- Q3: "Each socket type has exactly one maker row" as normative text.
- Q4: the name of the type `accept` returns. **C:** `UnixConn`. **S:** a name that says the side.

#### Phase A — Independent proposals

Five seats proposed the maker row and a new type for the accepted stream. They differed on the rule wording: sys, web and aiml gave the maker row plus a peer-address exception; plt and devops added a clause for traffic from peers the caller does not name. Min proposed that the row follow the kind of socket, with one `UnixStream` type for both sides. Every seat rejected an empty row for `close`, `local_addr` and `set_timeout`.

- **Systems:**

> **Opener rule.** A method on an open socket has the row of the std function that opened the socket (its
> *opener*). A method that takes a peer address as an argument has `Net.Connect` in place of the opener's
> row. A method has one static row, so a socket type has exactly one opener row: when two openers with
> different rows make a socket, each gives its own type.

- **Web/Scripting:**

> A method on a second-tier value carries the row of the function that made the value. A method that does
> something the maker's row does not cover carries the row of that act as well. Sending to an address that
> the caller names is such an act: it needs `Net.Connect`. Each second-tier type has one maker row. If two
> functions with different rows would make the same type, they make two types.

- **PLT:**

> The row of a method on an open socket comes from two clauses.
> 1. **Act.** A method that reaches a peer that the caller names carries `Net.Connect`. A method that takes traffic from peers that the caller does not name carries `Net.Listen`.
> 2. **Provenance.** Any other method on an open socket (data to or from the peer the socket already has, socket options, address queries, `close`) carries the row of the function or method that made the socket.

- **DevOps/Tooling:**

> Each method on an open socket has the row that this rule gives:
> 1. A method that reaches a peer that the socket is not tied to has the effect of making that reach. Sending to a caller-given address is `Net.Connect`. Taking a new peer (`accept`, or `recv_from` on a bound socket, which takes data from any sender) is `Net.Listen`.
> 2. Every other method has the row of the std function that made the socket. This includes reads and writes on an existing channel, and `local_addr`, `set_timeout` and `close`.
> 3. A socket type has exactly one maker row. If two functions with different rows make sockets, they return different types.

- **AI/ML:**

> A method on an open socket carries the row of the call that made the socket. The one exception is a method that sends to an address that the caller names in the call: it carries `Net.Connect`.

- **Minimalism:**

> **Rule.** Every method on an open socket has a row. The row comes from the kind of socket, not from the method and not from the function that made the value:
>
> - A **bound or listening socket** (`UdpSocket`, `UnixListener`) has `Net.Listen` on each method.
> - A **connection** (`UnixStream`, from `accept` or from `unix_connect`) has `Net.Connect` on each method.
> - A method that **sends to a peer named by an argument** has `Net.Connect`. Today that is only `send_to`, and its row is already decided.

#### Phase B — Debate highlights

One round. All six seats ended it ready to vote.

- **Min withdrew min-1** (the row follows the kind of socket) because a server would hold `Net.Connect`, which is also the row of `net.request`:

> My Phase A table said min-1 "opens no hole". That is wrong, and aiml-2's tradeoff note shows why. Under min-1 every Unix server must hold `Net.Connect`. `Net.Connect` is also the row of `net.request` (04_effects.md:290, :385). So a local socket server that only answers its own clients gets the right to dial out to any host. That is the same kind of hole I used to reject the union row (min-0 / G3), only in the other direction. I cannot reject one and keep the other.

- **Aiml, web and devops withdrew their fallbacks** (aiml-2, web-2, devops-2):

  AI/ML:

> I withdraw aiml-2 and oppose min-1. min-1's table lists the problem with the by-kind rule as "none". It leaves out one row of evidence:

  Web/Scripting:

> I withdraw web-2 (`Net.Socket`) as a fallback. G1 has the votes, and a new child would add a third name to

  DevOps/Tooling:

> **Support G1** (sys-1, web-1, plt-1, devops-1, aiml-1). **Oppose G2** (min-1), **G3**, and now **G4** too: since G1 has a majority of seats, I drop my own devops-2 fallback. Nobody backs empty rows, so that is settled.

- **Plt dropped the Listen half of its act clause** because of the DNS-client case:

> plt-1 and devops-1 had a symmetric act clause ("takes traffic from peers the caller does not name → `Net.Listen`"). sys, web and aiml have only the Connect exception. The rows are the same today. They differ only on a future socket that a `Net.Connect` function made and that can receive from any peer. Example: a future unbound UDP socket used as a DNS client, which calls `send_to(resolver)` and then `recv_from()`. The kernel does not filter that reply by sender.
>
> - With my Listen clause, that DNS client must declare `Net.Listen`. This is the over-asking I argued against in G2, so my own clause fails my own test.
> - Without it, the socket stays `Net.Connect`, which is correct for §4 line 13: a socket that a Connect function made is not a listening socket. The capability property that matters ("Connect alone cannot open a listening endpoint") holds by construction.

- **Devops kept the act clause:**

> I keep the act clause (plt-1, devops-1): "taking traffic from peers that the caller does not name (`accept`, `recv_from`) is `Net.Listen`". The rows today are the same either way, but the wording decides future methods, and that is what the ticket asks for:

- **"In its place", not "also carries"** (plt):

> On "also carries" vs "carries": for `send_to` on `udp_bind`'s socket, "also" gives `! Net.Listen, Net.Connect` and the plain exception gives `! Net.Connect` (the decided row, :1109). The decided row stays as it is. So the text must say the address clause *replaces* the maker row for that method: "carries `Net.Connect` in place of the maker row". That is sound: `sendto` with a bound fd does no listening act. I flag this so the writer copies the decided row and not the union.
>
> A method on an open socket carries the row of the function or method that made the socket. A method that sends to a peer address that the caller gives as an argument carries `Net.Connect` in its place. Each socket type has exactly one maker row: when two std functions with different rows make sockets, they return different types.

#### Phase C — Silent vote

| Question | Result |
|---|---|
| Q1 G1 | **yes 6-0** |
| Q2 rule text | **M 5-1** (DevOps *(dissent)*: A; sys and aiml moved from A back to M) |
| Q3 one maker row per type | **yes 6-0** |
| Q4 name | **C `UnixConn` 6-0** |

Each seat's vote, reasoning and concern:

- **Systems:**

  - Q1 G1 (maker row; split the stream type) — **yes**

    > **Reasoning:** Every method here is one syscall on an fd, and each one reads or changes kernel state that
    > another holder of the fd can see, so no row can be empty. The maker row is the tightest sound row: a client
    > holds `Net.Connect` alone and a server holds `Net.Listen` alone, so neither gets authority it did not already
    > need to get the socket. Splitting the stream type costs nothing at run time: both types are `{ fd: Int }` over
    > the same runtime intrinsics, and the row is erased before codegen.
    >
    > **Concern:** The writer may fold both stream types onto one C wrapper set and then let a later edit give one
    > side's method the other side's row, because the two traits look the same in the source.

  - Q2 rule text — **M**

    > **Reasoning:** I move back from A to M. In B1 I said that a socket the kernel binds to a free port on the first
    > `sendto` takes datagrams from any source, so `recv_from` on it is a listening act. That is true at the kernel
    > level, but every UDP client works that way (DNS, NTP, QUIC). If a Connect-only client had to hold `Net.Listen`
    > to read its own reply, we would get the over-asking that G3 was rejected for. plt's B1 makes the same point
    > about its own clause. Under M, the gate for "this socket takes traffic from strangers" sits at the maker, which
    > is also where the kernel decides it (`bind`). M also matches the decided `send_to ! Net.Connect` row with no
    > extra clause.
    >
    > **Concern:** A later maker with a `Net.Connect` row could return a socket that is in effect a server (for example
    > a fixed-port bind hidden behind a "connect" name); the panel for that gate must give it a `Net.Listen` maker row.

  - Q3 one maker row per type — **yes**

    > **Reasoning:** A method has one static row, and v1 has no effect-kinded generics, so a type that two makers with
    > different rows return can only get the union row. The union row is G3, which every seat rejected. Without this
    > sentence, the next socket type falls back to the union with no vote. The split costs no runtime and no layout.
    >
    > **Concern:** A later "any stream" trait over both types must take the union row with narrowing impls (§3.6), and
    > a writer may instead merge the two types again to get one type to pass around.

  - Q4 name of the type `accept` returns — **C**

    > **Reasoning:** In B1 I said that I would take the name web and aiml chose, and both back `UnixConn`. The name has no
    > cost in codegen, and it is short. A side-naming word would tell the reader the row, but the one line the
    > writer adds ("`accept` returns a `UnixConn`; `unix_connect` returns a `UnixStream`") and an error that names the
    > other type and its maker give the same information.
    >
    > **Concern:** A Go reader may expect `unix_connect` to return a `UnixConn`, because Go's `net.UnixConn` covers both
    > ends, and the first sign of the mistake will be a row error at a call site, not at the declaration.

- **Web/Scripting:**

  - Q1 G1 (maker row; split the stream type) — **yes**

    > **Reasoning:** The row a dev writes first is right: a server writes `! Net.Listen`, a client writes
    > `! Net.Connect`, and every method on the socket they got back works with no more names. Both §4.4.6
    > examples stay as written, and type inference hides the new type in the common case. The other options
    > make a server hold outbound HTTP (min-1) or make a client hold `Listen` (union row). Each of those would
    > start a "why does my code need X?" question that no error message can answer well.
    >
    > **Concern:** A Go-trained dev will write `UnixStream` in a server helper signature, so the type-mismatch
    > error must name the type that `accept` returns and its row, or the split reads as an arbitrary rule.

  - Q2 rule text — **M**

    > **Reasoning:** One rule plus one exception fits in one sentence of an error message: "needs `Net.Listen`
    > because `udp_bind` made this socket". Today the act clause gives the same rows, so its only effect is on a
    > future socket that a `Net.Connect` call makes and that takes traffic from any peer. There I agree with min:
    > the panel that adds that maker should give the maker `Net.Listen`, so that the client does not pay a row on
    > each receive. Clause (2) also makes the rule ask "who can send to this socket?" for each method, which is a
    > question about the kernel that a scripting dev cannot answer from the signature.
    >
    > **Concern:** If A wins, a later Connect-made UDP client must hold `Net.Listen` to read its own reply. That
    > is the client-side hole that every seat rejected in G3.

  - Q3 one maker row per type — **yes**

    > **Reasoning:** Without this sentence, the maker rule does not say what to do when two makers share a type,
    > and the next socket gate falls into the same `UnixStream` trap. It keeps the rule mechanical: a dev (or the
    > spec writer) reads the type and knows the row. It costs nothing to state.
    >
    > **Concern:** A later gate may add a third maker to a type (for example a `socketpair`-style constructor)
    > and then must add one more type, so the stream type count can grow faster than users expect.

  - Q4 name of the type `accept` returns — **C (`UnixConn`)**

    > **Reasoning:** It is short, Go uses it, and `serve_once` already calls the variable `conn`. A longer name
    > that says the side costs tokens in every helper signature, and the one-line spec sentence ("`accept`
    > returns a `UnixConn`; `unix_connect` returns a `UnixStream`") plus the diagnostic give the side.
    >
    > **Concern:** In Go, `net.UnixConn` is the type for both ends, so some readers will take `UnixConn` to be
    > the general type until the first error tells them otherwise.

- **PLT:**

  - Q1 G1 (maker row; split the stream type) — **yes**

    > **Reasoning:** Each row is non-empty, so rule 2 and the §4.1 purity claim hold. Each row is also least-privilege: no method asks for authority the holder did not already need to get the socket. The rule is the second-tier image of rule 3 (the maker of a value decides the effect of operations on it), so one idea covers handle ops and second-tier values. With no effect-kinded generics in v1, a type split is the only static way to keep both properties for a stream that two makers can return.
    > **Concern:** A later gate may add a function that accepts "any Unix stream" and give it the union row by habit, when it should use a shared trait whose impls narrow.

  - Q2 rule text — **M**

    > **Reasoning:** The two wordings differ only on a socket that a `Net.Connect` function made and that receives from senders it did not name. The example sys, devops and aiml give is an unbound UDP socket that the kernel binds to an ephemeral port at the first `sendto`. Under A, its `recv_from` needs `Net.Listen`. But `Net.Listen` also lets the code call `udp_bind` and `unix_listen` on a port or path it picks, so a DNS client that only reads its own reply would hold the full server capability. That is the over-grant every seat rejected in G3. An ephemeral port that the code cannot pick and that opens only after an outbound send is a Connect-shaped act (stateful firewalls treat it the same way), and M gives it `Net.Connect`. M is also the more compositional text: one default, one override, and no case where two clauses can both match with different rows.
    > **Concern:** If A wins, the first connect-made UDP client will have to declare `Net.Listen` to read its own reply, and every manifest for such a client will grant the right to bind any port.

  - Q3 one maker row per type — **yes**

    > **Reasoning:** Without this sentence the rule is incomplete: it has no answer for the next type that two makers with different rows return, and a writer will fall back to the union row (G3) without a vote. With it, the maker rule is a total function from (type, method) to row, which is what rule 2 needs for every later socket method.
    > **Concern:** A later writer may meet the sentence by adding a near-copy type each time instead of asking whether the two makers really need different rows.

  - Q4 name of the type `accept` returns — **C (`UnixConn`)**

    > **Reasoning:** The row is in the type, so the name only needs to tell the two types apart, and `UnixConn` vs `UnixStream` does that. The type error the writer adds ("`accept` returns `UnixConn`; `unix_connect` returns `UnixStream`") covers the one risk, Go readers who expect `UnixConn` on both ends. I see no soundness gain from a longer name.
    > **Concern:** Go-trained readers will write `UnixConn` for a client stream until the diagnostic corrects them.

- **DevOps/Tooling:**

  - Q1 G1 (maker row; split the stream type) — **yes**

    > **Reasoning:** G1 is the only option where the fix that `UndeclaredEffect` suggests never adds a capability that the code does not use. A server stays at `! Net.Listen`, which matches the §4.4.2 `start_server` precedent, and a client stays at `! Net.Connect`, so 04_effects.md:13 and the lockfile audit stay true. Hover and completion show one fixed row per method, with nothing to work out from data flow.
    > **Concern:** With Go habits, users (and models) will write `UnixConn` for a client stream. If the type-mismatch error does not name both makers ("`accept` returns `UnixConn`; `unix_connect` returns `UnixStream`"), this becomes a common Stack Overflow question.

  - Q2 rule text — **A *(dissent)***

    > **Reasoning:** The rule exists to give rows to methods nobody has written yet, and those rows end up in manifests and audit diffs. Under M, a socket that a `Net.Connect` function makes and that then takes datagrams from any sender gets `Net.Connect`. The audit then shows a "dial-only" package that in fact receives from the whole network, and no tool can see that. plt's DNS-client case is real, but the kernel does not filter that reply by sender. So `Net.Listen` is the honest row there, and a future API that filters by peer (a `connect`-ed UDP socket) is the place to remove it.
    > **Concern:** If M wins, a later Connect-made UDP socket will get `recv_from ! Net.Connect` by rule with no vote, and the budget check will pass a package that receives from any sender.

  - Q3 one maker row per type — **yes**

    > **Reasoning:** Without this sentence, the next type that two makers return gets a union row (G3) by default. That puts back the fix-suggests-an-escalation diagnostic that every seat rejected. With it, a stdlib review or a ratchet can check the rule by reading signatures.
    > **Concern:** A later writer may see the split as duplicate surface and merge the types "for convenience", and no compiler check would stop that.

  - Q4 name of the type `accept` returns — **C (`UnixConn`)**

    > **Reasoning:** It is short, it does not rank next to `UnixStream` in completion by prefix, and an error line shows it clearly next to `UnixStream`. The side shows in the maker note in the diagnostic, and the type name does not need to carry it. `UnixAccepted` and `UnixServerConn` cost tokens in every signature for no gain in tooling.
    > **Concern:** Go's `net.UnixConn` is the type for both ends, so the name carries a wrong prior. The maker note in the diagnostic must cover that.

- **AI/ML:**

  - Q1 G1 (maker row; split the stream type) — **yes**

    > **Reasoning:** A model can get every row from one rule and the line that opened the socket, which is nearly always in the same function. Both §4.4.6 examples stay correct as written, so the code that models copy needs no change. The client example (`ask ! Net.Connect`) shows the one side the spec does not show today. No other option keeps one meaning for each Net child.
    > **Concern:** Models with Go or Rust priors will write `UnixStream` in the signature of a helper for an accepted stream. If the type-mismatch error does not name `accept` as the maker of the other type, each such error costs a retry.

  - Q2 rule text — **M**

    > **Reasoning:** In B1 I moved to A. plt's B1 DNS-client case moved me back. With a Connect-made socket that calls `send_to(resolver)` and then `recv_from()`, A makes a plain client declare `Net.Listen`. Then every client manifest lists `Listen`, and both a model and an auditor lose the signal of §4 line 13. M is also easier for a model to apply: one maker row plus one exception that a model checks against the signature (does an argument name a peer?). A instead asks for a per-method judgment ("does this take traffic from peers it does not name?"), and that is the kind of judgment call that left four methods with no row. Today the rows are the same (`UdpSocket` has no unbound constructor, 04_effects.md:1120), so M costs nothing now.
    > **Concern:** The writer must copy "carries `Net.Connect` in its place", not "also carries", or `send_to` silently becomes the union and contradicts the decided row at :1109.

  - Q3 one maker row per type — **yes**

    > **Reasoning:** Without this sentence the rule cannot answer the next type that two makers return, and a writer or a model will fall back to the union row with no vote. With it, a later socket type gets its rows with no new vote, which is what this ticket asks for. It is one sentence, and it states the reason for the `UnixConn` split, so a model can see why two types have the same methods.
    > **Concern:** Someone may read the sentence as a ban on a later shared trait over both stream types. The spec should not suggest that, because a shared trait whose impls narrow the row stays sound (E0904).

  - Q4 name of the type `accept` returns — **C (`UnixConn`)**

    > **Reasoning:** It is short, so a model pays few tokens in each helper signature, and `serve_once` already names the variable `conn`. It cannot be confused with `UnixStream` in completion or in an error line. A side-naming name (`UnixServerConn`, `UnixAccepted`) adds tokens on every use. The one line the writer adds ("`accept` returns a `UnixConn`; `unix_connect` returns a `UnixStream`") and the mismatch diagnostic carry the same information for less.
    > **Concern:** In Go, `UnixConn` is the type for both ends, so a model may use it for the result of `unix_connect`. Only the diagnostic text guards against that.

- **Minimalism:**

  - Q1 G1 (maker row; split the stream type) — **yes**

    > **Reasoning:** G1 adds one type and one trait, and it changes the meaning of no effect. Every other option either widens a grant (G2 gives each server outbound `Net.Connect`; G3 widens both sides) or adds an effect name (G4). A new type with three methods costs less surface than an effect with two meanings. Both §4.4.6 examples stay as written, so the change to the spec text is small.
    >
    > **Concern:** Someone will add a shared "any Unix stream" trait before a real program needs one; it should wait until a program needs it.

  - Q2 rule text — **M**

    > **Reasoning:** M is two sentences and gives every row today. The act clause in A decides no row now. It only matters for a `Net.Connect` maker that gives a socket that receives from any sender, and the UDP gate ruled out that maker (no unbound constructor, 04_effects.md:1115). B1 also showed that the clause is not clearly right for that case: sys and devops say it keeps 04_effects.md:13 true, web and plt say it makes a DNS-style client hold `Net.Listen`. A rule clause whose correct answer the panel cannot agree on for the one case it covers should not go in the spec before the case exists. The panel that adds such a maker can decide its row then.
    >
    > **Concern:** If A wins, the writer must keep `send_to` at `Net.Connect` alone (the decided row), not the union of clauses 1 and 3.

  - Q3 one maker row per type — **yes**

    > **Reasoning:** Without this sentence the rule has no answer for the next type that two makers return, and a writer will fall back to the union row with no vote. One sentence closes the rule, and so no later socket method needs a panel. It adds no syntax and no name; it only states what G1 already does for `UnixConn` and `UnixStream`.
    >
    > **Concern:** The sentence can cause one more type at each later gate (TCP accept vs connect); each gate must check that the split is still worth a type and not reach for a new effect instead.

  - Q4 name of the type `accept` returns — **C (`UnixConn`)**

    > **Reasoning:** It is short, Go readers know it, and inference hides it in most code (`let conn = listener.accept()?`). A longer name that says the side costs tokens in each helper signature, and the information it adds is already in one line of spec text and in the type-mismatch error.
    >
    > **Concern:** A Go-trained reader may expect `UnixConn` from `unix_connect` too; the spec line "`accept` returns a `UnixConn`; `unix_connect` returns a `UnixStream`" and the mismatch error must carry that.

The Q2 dissent (DevOps), in the seat's own words:

> **Concern:** If M wins, a later Connect-made UDP socket will get `recv_from ! Net.Connect` by rule with no vote, and the budget check will pass a package that receives from any sender.

The majority answer (Systems, Q2 concern): the gate sits at the maker. A later maker with a `Net.Connect` row that is in effect a server must get a `Net.Listen` maker row at its own gate.

#### Phase D

Not triggered. The closest result was Q2 at 5-1.

### Final Spec

```blink
// Makers and their rows
pub fn udp_bind(addr: SockAddr) -> Result[UdpSocket, NetError] ! Net.Listen
pub fn unix_listen(path: Str) -> Result[UnixListener, NetError] ! Net.Listen
pub fn unix_connect(path: Str) -> Result[UnixStream, NetError] ! Net.Connect

// A method on an open socket carries the row of its maker.
// A method that sends to a caller-given peer address carries Net.Connect in its place.
pub trait UdpSocketOps {
    fn recv_from(self, *, max: Int = 65535) -> Result[(Bytes, SockAddr), NetError] ! Net.Listen
    fn send_to(self, data: Bytes, dest: SockAddr) -> Result[(), NetError] ! Net.Connect
    fn local_addr(self) -> Result[SockAddr, NetError] ! Net.Listen
    fn set_timeout(self, ms: Int) ! Net.Listen
    fn close(self) ! Net.Listen
}

pub trait UnixListenerOps {
    fn accept(self) -> Result[UnixConn, NetError] ! Net.Listen
    fn close(self) ! Net.Listen
}

// Two stream types, one maker row each
pub trait UnixConnOps {          // made by accept
    fn read_line(self) -> Result[Str?, NetError] ! Net.Listen
    fn write(self, data: Str) -> Result[(), NetError] ! Net.Listen
    fn close(self) ! Net.Listen
}

pub trait UnixStreamOps {        // made by unix_connect
    fn read_line(self) -> Result[Str?, NetError] ! Net.Connect
    fn write(self, data: Str) -> Result[(), NetError] ! Net.Connect
    fn close(self) ! Net.Connect
}

fn ask(path: Str, question: Str) -> Result[Str?, NetError] ! Net.Connect {
    let conn = unix_connect(path)?
    conn.write("{question}\n")?
    let reply = conn.read_line()?
    conn.close()
    Ok(reply)
}
```

Locked points:

- A method on an open socket carries the row of the function or method that made the socket. A method that sends to a peer address that the caller gives as an argument carries `Net.Connect` in its place. "In its place" is the wording: `send_to` stays `! Net.Connect` alone, the row that §4.4.6 already gave. The wording "also carries" is not used, because it would make `send_to` carry the union.
- Each socket type has exactly one maker row: when two std functions with different rows make sockets, they return different types. The sentence does not bar a later trait over both stream types. Such a trait takes the union row and each impl narrows it (§3.6, E0904). No such trait is added now.
- `UdpSocket.recv_from`, `local_addr`, `set_timeout` and `close`, and `UnixListener.close`, are `! Net.Listen`. `udp_bind` made the socket and `unix_listen` made the listener.
- `UnixListener.accept` returns `Result[UnixConn, NetError]` and keeps `! Net.Listen`. `UnixConn` has `read_line`, `write` and `close`, each `! Net.Listen`.
- `unix_connect` keeps returning `UnixStream`. Its `read_line`, `write` and `close` are `! Net.Connect`.
- The name is `UnixConn`. The spec says in one line that `accept` returns a `UnixConn` and `unix_connect` returns a `UnixStream`. When one is given where the other is expected, the type-mismatch error names the other type and the function that makes it.
- No row is empty. No new effect is added: the `Net` tree keeps `Connect`, `Listen` and `DNS`.
- `echo_once` and `serve_once` stay as written. `serve_once` types against `UnixConn`. A client example, `ask ! Net.Connect`, is added.
- `read_line` spells its result `Result[Str?, NetError]` (the one-spelling rule in DECISIONS.md).
- The removed-functions row for `socket_read_line`, `socket_write` and `unix_socket_close` names both stream types, with `Net.Connect` on `UnixStream` and `Net.Listen` on `UnixConn`, because the old functions served both sides.

### Amendments

None.

### Implementation notes

These are not spec text.

- `lib/std` has no UDP or Unix socket types yet (`net.bl`, `net_tcp.bl` and `net_error.bl` only). The change costs no code today.
- Both stream types can share one runtime wrapper, because both are `{ fd: Int }`. A later edit must not give one side the other side's row (sys). The two traits look the same in the source.
- The `lib/std` TCP methods (`TcpSocketOps`, `TcpListenerOps.close`) declare no rows today. TCP is not in `sections/`. Its rows are a separate question.
- The earlier panel record says the moderator filled in the Unix method sets (`decisions/effect-tracked-builtins.md`, "Details the moderator filled in while writing the spec text"). The ballot did not decide them, and a later panel may change them. This panel changed them.

### Open cases and follow-ups

- A later maker with a `Net.Connect` row can return a socket that takes datagrams from any sender, such as a UDP client socket that the kernel binds on the first send (devops, the Q2 dissent). By the rule, its `recv_from` would be `Net.Connect`. If such a maker is in effect a server, it must get a `Net.Listen` maker row at its own gate (sys).
- A shared "any Unix stream" trait waits for a real program that needs it (min, plt). It takes the union row, and its impls narrow (§3.6, E0904).
- Each later gate that meets the one-maker-row sentence must check that the split is worth a type, not reach for a new effect (min), and that a near-copy type is not automatic (plt).
- A mismatch between `UnixConn` and `UnixStream` is a likely first error for readers who know Go, where `net.UnixConn` covers both ends. The diagnostic must name the maker of the other type (all six seats).
- `Closeable.close` and `Scoped.exit` have empty rows, but the spec's own impls widen them, which E0904 forbids. That is a separate open spec question. These sockets do not implement `Closeable`, so this decision does not wait for it.
