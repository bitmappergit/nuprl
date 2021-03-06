


letrec ExplodeProduct i new_ids =
Try
(  ComputeHyp i
   THEN
   (\ p .
      let n = number_of_hyps p   
      and (),(),B = destruct_product (type_of_hyp i p) in
      let new1 . new_ids = new_ids  in
      let new2 =
         if is_product_term B then `NIL`
         else hd new_ids      in
      (  Refine (product_elim i new1 new2)
         THEN (\p. if number_of_hyps p > n+2 then ThinToEnd (n+3) p else Idtac p)
         THEN Thinning [i]
         THEN ApplyToLastHyp (\i. ExplodeProduct i new_ids)
      ) p
   )
)  
;;




%
let BringHyps hyps p =
   letrec build_seq_term decls =
      if length decls = 1 then snd (destruct_declaration (hd decls))
      else let x,A = destruct_declaration (hd decls)  in
           make_function_term x A (build_seq_term (tl decls))     in
   (  Seq [build_seq_term (map (\i. select i (hypotheses p)) hyps)]
      THENL [Idtac;\p. ( RepeatFunctionElimFor (length hyps) THEN Hypothesis]
   ) p
;;
%


let SquashAndBringHyps hyps p =
  (   let squashed_hyps = map (\i. make_squash_term (type_of_hyp i p)) hyps   in
   letrec make_seq_term l =
      (let h.t = l in make_implies_term h (make_seq_term t))
      ? (concl p) in
   let n = number_of_hyps p   in
   Seq [make_seq_term squashed_hyps]
   THENL [Thinning hyps
         ;RepeatFunctionElimFor (n+1) (length hyps) []
      THEN IfThenOnConcl is_squash_term SquashIntro 
      THEN Thinning [n+1]
         ]
  ) p
;;



let ExplodeTaggedProduct i new_ids =
   letrec Aux i new_ids junk_hyps p =
      (let (),(),B = destruct_product (type_of_hyp i p) in
       let x = hd new_ids 
       and rest = tl new_ids
       and y = if is_product_term B then new_id p else second new_ids   in
       ( Refine (product_elim i x y)
         THEN Aux (number_of_hyps p + 2) rest (i.junk_hyps) 
       ) p
      )
      ? Thinning junk_hyps p        in
   ComputeHyp i 
   THEN (\p. Aux i new_ids [i] p)
;; 



letrec explode_product t =
   (let x,A,B = destruct_product t  in
    (x,A).(explode_product B)
   )
   ? [`NIL`,t]
;;


let make_projection tuple_length component_number t =
   let p1 t = make_spread_term t (make_bound_id_term [`x`;`y`] (make_var_term `x`))
   and p2 t = make_spread_term t (make_bound_id_term [`x`;`y`] (make_var_term `y`)) in
   letrec aux tl cn t =
      if cn = 1 then p1 t
      if tl = 2 & cn = 2 then p2 t
      else aux (tl-1) (cn-1) (p2 t)    in
   if component_number < 1 or component_number > tuple_length or tuple_length <2 then
      failwith `make_projection`
   else aux tuple_length component_number t
;;


letrec explode_function t =
   let x,A,B = destruct_function t ? failwith `explode_function`  in
   if is_function_term B then 
      let l,t' = explode_function B in ((x,A).l),t'
   else
      [x,A],B
;;

% Filters out `NIL` ids %
letrec make_lambdas ids t =
   if null ids then t
   if hd ids = `NIL` then make_lambdas (tl ids) t
   else make_lambda_term (hd ids) (make_lambdas (tl ids) t)
;;


letrec implode_product exploded_product =
   if length exploded_product = 1 then snd (hd exploded_product)
   else let (x,A).rest = exploded_product in make_product_term x A (implode_product rest)
;;


letrec implode_function domains range =
   if null domains then range
   else let (x,A).rest = domains in make_function_term x A (implode_function rest range)
;;


let first_equand t  =
   let (t'.rest),() = destruct_equal t    in
   t'
;;



letrec RepeatExtensionalityThen Tactic p =
   if is_function_term (fast_ap compute (concl_type p)) then
      (ComputeConclType 
       THEN Refine (extensionality big_U [] (undeclared_id p `x`))
       THENM RepeatExtensionalityThen Tactic) p
    else Tactic p
;;








let ExplodeProductImage i function_ids arg_ids p =
   % Assume hypothesis i is of the form (modulo computation of the whole type or the product part)
     f: (x1:A1->...xm:Al->y1:B1#...#yn:Bm   where some yi,xi may be NIL. 
     Let [f1;f2;...;fn] be function_ids %
   let n = length function_ids   in
   let main_function_id = % f % if `NIL` = id_of_hyp i p then undeclared_id p `f` else id_of_hyp i p  in
   let domains, range =
      % [x1,A1; ... ; xm,Al], y1:B1#...yn:Bm %
      explode_function (compute (type_of_hyp i p)) in
   let m = length domains  in
   let domains = % Set NIL xi to ids from arg_ids %
                 letrec add_ids domains arg_ids =
                     if null domains then []
                     else let (x,A).rest = domains in 
                          if x=`NIL` then (hd arg_ids, A) . add_ids rest (tl arg_ids)
                          else  (x, A) . add_ids rest arg_ids     in   
                 add_ids domains arg_ids
                 ? failwith `ExplodeProductImage: need more arg. ids`      in
   let domain_ids = map (\x. fst x) domains  in
   if not null (intersect (union domain_ids function_ids) (map (\x. id_of_declaration x) (hypotheses p)))
      or not null (intersect function_ids domain_ids) then failwith `ExplodeProductImage: id conflict.` ;
   let exploded_range = % [y1,B1;...;yn,Bn] % explode_product (compute range)  in
   let domain_vars = map (\x. make_var_term x) domain_ids   in
   let values_of_new_functions =
      % [...; fi(x1)...(xm); ...] %
      map (\f. iterate_fun (\x. make_apply_term x)
                           (make_var_term f . domain_vars))
          function_ids  in
   let value_of_main_function =
      % f(x1)...(xm) %
      iterate_fun (\x. make_apply_term x) (make_var_term main_function_id . domain_vars) in
   letrec build_new_image_types substitutions i =
      if i > length exploded_range then []
      else  let x,B = select i exploded_range   in
            substitute B substitutions
            .
            build_new_image_types ((make_var_term x, select i values_of_new_functions) . substitutions) (i+1)  in
   let new_function_types =
      % [...; x1:A1->...->xm:Am -> Bi[fj(x1)...(xm)/xj, 1j<i]; ...] %
      map (\B. implode_function domains B) (build_new_image_types [] 1)   in
   let tuplized_new_functions =
      make_lambdas domain_ids (reverse_iterate_fun (\x. make_pair_term x) values_of_new_functions) in
   let equality_term = make_equal_term (type_of_hyp i p) [make_var_term main_function_id; tuplized_new_functions]   in
   let desired_sequent_suffix =
      % f1:f1_type -> . . . -> fn:fn_type -> f=\x1....\xm.<f1....> in range -> original_conclusion %
      implode_function ((function_ids com new_function_types) @ [`NIL`, equality_term]) (concl p)  in
   let lemma_for_desired_sequent_suffix =
      % x1:A1 -> ... -> xm:Am -> z:range -> (...& z.i in B[z.j/xj,1j<i] & ... & z=<z.1,...> in range)
        where z.i is the pile of spreads on z which will project the i-th member of the n-tuple z. %
      let z = make_var_term (undeclared_id p `z`)  in
      let z_projections = map (\i. make_projection n i z) (upto 1 n) in
      letrec types_for_projections substitutions i =
         if i>n then []
         else  let x,B = select i exploded_range   in
               substitute B substitutions
               . types_for_projections ((make_var_term x, select i z_projections) . substitutions) (i+1) in
      let projection_membership_assertions =
         map (\zi,T. make_equal_term T [zi]) (z_projections com (types_for_projections [] 1))   in
      let z_equals_projections = make_equal_term range [z; reverse_iterate_fun make_pair_term z_projections]   in
      implode_function
         domains
         (make_function_term
            (destruct_var z) 
            range
            (make_conjunction (projection_membership_assertions @ [z_equals_projections])))  in
   let ApplyLemma = % Assume that the last m hypotheses declare vars which can be used to instantiate the xi %
      (\p'. RepeatFunctionElimFor (number_of_hyps p + 2) m
               (map (\i. make_var_term (id_of_hyp i p')) (upto (number_of_hyps p' - (m-1)) (number_of_hyps p')))
               p'
      )
      THEN (\p. if not is_var_term (first_equand (concl p)) ? false then
                  ApplyToLastHyp BackThruHyp p
                else Idtac p
           )   in

(  Seq [desired_sequent_suffix]
   THENL [RepeatFor (length function_ids +1) Intro 
         ;Seq [lemma_for_desired_sequent_suffix]
          THENL   [RepeatFor (length domains + 1) Intro
                   THENW ((\p. ExplodeTaggedProduct (number_of_hyps p) (map (\(). new_id p) function_ids) p)
                          THEN Repeat Intro THENW ReduceConcl) 
                  ;% Prove the goal using the two seq'd in fmlas by first eliming the first fmla on
                     on the functions formed from f by using projections, e.g., \x1...\xm. (f...(xm)).i,
                     then using the second seq'd in fmla to prove the n membership subgoals and the one equality subgoal %
                   RepeatFunctionElimFor (number_of_hyps p + 1) (n+1)
                                         (map (\i. make_lambdas domain_ids (make_projection n i value_of_main_function))
                                              (upto 1 n))
                   THENL (  (replicate (ReduceConcl 
                                        THEN (RepeatFor m (\p. if is_wf_goal p then fail  else MemberIntro p))
                                        THENW ApplyLemma)
                                       n)
                          @ [ ReduceConcl                
                              THEN Try (RepeatExtensionalityThen  (ReduceConcl THEN ApplyLemma))
                              THEN Try (\p. (if is_lambda_term (head_of_application (first_equand (concl p)))
                                             then ReduceConcl
                                                  THEN Repeat (\p. if is_lambda_term (first_equand (concl p)) then MemberIntro p else fail)
                                                  THEN IfThenOnConcl
                                                         (\t. is_pair_term (first_equand t))
                                                         ((\p. Seq [make_equal_term range [value_of_main_function; first_equand (concl p)]] p)
                                                          THENL [ApplyLemma; Refine equality])
                                             else fail
                                            ) p
                                       )
                             ;Hypothesis
                             ]
                          )
                  ]
         ]
)  p
;;

let is_arith_exp t =
   member_of_tok_list (term_kind t) [`ADDITION`; `MULTIPLICATION`; `SUBTRACTION`; `DIVISION`; `MODULO`; `MINUS`]
;;

letrec is_arith_fmla t =
   if is_equal_term t then
      (let eqs,() = destruct_equal t in null (filter (\x. not is_arith_exp x) eqs))
   if is_less_term t then true
   if is_not_term t then is_arith_fmla (destruct_not t)
   else false
;;




let SetElimForArith p =
   if not is_arith_fmla (concl p) then failwith `SetElimForArith` 
   else
      reverse_iterate_fun
         (\T T'. T THENM T')
         (map (\i. IfThenOnHyp i (\x,A. is_set_term (fast_ap compute A)) (Elim i))
           (filter (\x. not x=0)
                   (map (\x. find_declaration (destruct_var x) p)
                        (free_vars (concl p)))))
         p
;;




let SubstConclType t' p =

   let c = concl p   in
   if is_equal_term c then
      (  let eqs, t = destruct_equal c in
         ParallelSeq [make_equal_term (make_universe_term big_U) [t';t]
                     ;make_equal_term t' eqs
                     ]
         THENL [Idtac; Idtac; Refine equality]
      ) p
   else
               (  ParallelSeq [make_equal_term (make_universe_term big_U) [t';c]
                     ;t'
                     ]
         THENL [Idtac
               ;Idtac
               ;\p. let x = undeclared_id p `x` in
                    (TagHyp (number_of_hyps p) x
                     THEN Refine (explicit_intro (make_var_term x))
                     THEN Refine equality
                    ) p
               ]
      ) p

;;



letrec do_analogy pattern goal =
   if is_refined pattern then
      TRY (refine (adjust_assum_number pattern goal)
         THENTRYL (map do_analogy (children pattern))
          ) goal
   else IDTAC goal
;;



letref saved_proof = void_goal_proof;;

let mark goal_proof = (saved_proof := copy_proof goal_proof;
                       IDTAC goal_proof);;

let copy goal_proof =
  do_analogy saved_proof goal_proof;;



